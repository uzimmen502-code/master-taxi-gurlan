'use strict';

/**
 * СОТУВЧИНИНГ ЎЗ TELEGRAM КАНАЛИ (эга қарори 2026-10-25, «сотувчининг ўз ижтимоий саҳифалари» 1-фаза).
 *
 * Сотувчи ўз ОШКОРА (@username) каналига AVA ботини «Хабар жойлаш» ҳуқуқи билан администратор қилади; товар/хизмат
 * видеоси фаол бўлгач, AVA уни ўша каналга ҳам жойлайди (`tv_social_publish.js` — тармоқ `seller_telegram`).
 * Instagram/Facebook (Meta App Review) ва YouTube (Google audit) — кейинги фаза, бу ерда йўқ.
 *
 * Бот — AVA'нинг ЎША боти (`settings/tv_social.telegramBotToken`, фақат CF). Токен бошқа жойга ёзилмайди ва
 * лог/жавобга чиқмайди; бот номи `getMe`дан олинади (hardcode йўқ).
 *
 * ЭГАЛИКНИ ИСБОТЛАШ (PROPOSED): бот администратор бўлгани етарли эмас — бот бошқа сотувчининг (ёки AVA'нинг расмий)
 * каналида ҳам администратор бўлиши мумкин, шунда ҳар ким ўша канални «меники» деб улаб, унга ўз постларини
 * юбортирарди. Шунинг учун сервер бир марталик код беради (`AVA-XXXXXX`, 30 дақиқа), сотувчи уни канал ТАВСИФИГА
 * (description) ёзади, сервер `getChat().description`да кодни топса — канал уланади; кейин кодни ўчириш мумкин.
 * Тавсифни фақат канал админи ўзгартира олади — бу эгалик далили.
 *
 * Маълумот (фақат сервер ёзади; rules):
 *   seller_tg_channels/{ownerPhone}   — эганинг ҳолати: pending | connected | needs_reconnect | disconnected
 *                                        (chatId, username, title, code, codeExpiresAt, вақтлар, lastErrorCode).
 *                                        Эга ўз ҳужжатини `get` қила олади (жойлаш экрани чипи учун), ёзиш — йўқ.
 *   seller_tg_channel_chats/{chatId}  — бир канал = бир сотувчи (транзакция; фақат сервер).
 *
 * Callable'лар: sellerTgChannelStatus, sellerTgChannelPrepare, sellerTgChannelConnect, sellerTgChannelDisconnect.
 * Диагностика кодлари (`details.code`): TG_BOT_UNAVAILABLE, INVALID_USERNAME, PRIVATE_CHANNEL_UNSUPPORTED,
 * CHANNEL_NOT_FOUND, NOT_A_CHANNEL, CHANNEL_NOT_ALLOWED, BOT_NOT_ADMIN, BOT_NO_POST_RIGHT, CHANNEL_TAKEN,
 * SELLER_HAS_CHANNEL, SHOP_BLOCKED, NO_PENDING_CODE, CODE_EXPIRED, CODE_NOT_FOUND, CONNECT_STATE_CHANGED,
 * SELLER_TG_RATE_LIMIT (Prepare/Connect: соатига RATE_MAX тадан — умумий ботни Telegram 429'га итармаслик учун),
 * TG_TRY_LATER (Telegram 429/5xx/тармоқ — «кейинроқ уриниб кўринг», «топилмади/админ эмас» эмас).
 *
 * КАНАЛНИ ЎТКАЗИШ (review M3, 2026-10-26): индекс бошқа сотувчини кўрсатса ҳам, янги сотувчи ЎЗ кодини канал
 * тавсифига ёза олса — бу ҲОЗИРГИ эгалик далили: индекс янги сотувчига ўтади, эскисининг ҳужжати `disconnected`
 * (`lastErrorCode: CHANNEL_TRANSFERRED`) — бир транзакцияда. Кодсиз тиклаш (`needs_reconnect`) фақат индекс ҳали
 * ўша сотувчини кўрсатса.
 */
const axios = require('axios');
const crypto = require('crypto');
const shopLinks = require('./shop_links');
const page = require('./tv_clip_page');

const TELEGRAM_API = 'https://api.telegram.org';
const CHANNELS = 'seller_tg_channels';
const CHATS = 'seller_tg_channel_chats';
/// Prepare/Connect чақирувлари ҳисоблагичи (фақат сервер; rules — ёпиқ).
const RATE = 'seller_tg_rate_limits';
const RATE_WINDOW_MS = 60 * 60 * 1000;
const RATE_MAX = 10;
/// `tv_clips.socialNetworks` ичидаги қиймат ва `socialPost.networks.<id>` калити.
const NET = 'seller_telegram';
const CODE_TTL_MS = 30 * 60 * 1000;
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // адаштирадиган 0/O, 1/I/L йўқ
const CODE_LEN = 6;
const CODE_RE = /^AVA-[A-Z0-9]{6}$/;
/// Telegram ошкора номи: ҳарф билан бошланади, ҳарф/рақам/«_», 4–32 белги.
const USERNAME_RE = /^[A-Za-z][A-Za-z0-9_]{3,31}$/;
const BOT_CACHE_MS = 60 * 60 * 1000;
/// Telegram caption лимити 1024 — заҳира билан.
const CAPTION_MAX = 1000;
const ACTIVE = ['connected', 'needs_reconnect'];

const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

/** AVA Telegram боти созламаси — `tv_social_publish.js` ҳам шуни ишлатади (ЯГОНА манба). */
function telegramBotFromSettings(s) {
  const x = s || {};
  return {
    token: str(x.telegramBotToken, 200) || str(process.env.TELEGRAM_CHANNEL_BOT_TOKEN, 200),
    channelId: str(x.telegramChannelId, 80) || str(process.env.TELEGRAM_CHANNEL_ID, 80),
  };
}

/**
 * Фойдаланувчи киритган канал: `@name`, `name`, `t.me/name`, `https://t.me/name`. Ёпиқ канал таклифи
 * (`t.me/+…`, `joinchat`) — `{ private: true }`. Яроқсиз — `{ username: '' }`.
 */
function parseChannelInput(raw) {
  let s = str(raw, 200);
  if (/(^|\/)(\+|joinchat\/)/i.test(s.replace(/^https?:\/\//i, ''))) return { username: '', private: true };
  s = s.replace(/^https?:\/\//i, '').replace(/^(www\.)?(t|telegram)\.me\//i, '').replace(/^@/, '');
  s = s.split(/[/?#]/)[0];
  return USERNAME_RE.test(s) ? { username: s, private: false } : { username: '', private: false };
}

function newCode() {
  const bytes = crypto.randomBytes(CODE_LEN);
  let out = '';
  for (let i = 0; i < CODE_LEN; i += 1) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return `AVA-${out}`;
}

/** Канал тавсифида код борми (катта-кичик ҳарф фарқсиз; код атрофида бошқа матн бўлиши мумкин). */
function descriptionHasCode(description, code) {
  if (!CODE_RE.test(String(code || ''))) return false;
  return String(description || '').toUpperCase().includes(code);
}

/** Telegram хатоси: `code` — HTTP/`error_code`, `description` — Telegram матни (токенсиз). */
class TgError extends Error {
  constructor(code, description) {
    super(description);
    this.tgCode = Number(code) || 0;
    this.description = description;
  }
}

/**
 * Бот каналдаги ҳуқуқини йўқотгани (ёки канал йўқолгани): қайта улаш керак. 429/5xx/тармоқ узилиши — йўқ
 * (вақтинча хато, админ қайта уриниши етарли).
 */
function needsReconnectError(e) {
  if (!(e instanceof TgError)) return false;
  if (e.tgCode === 403) return true;
  return e.tgCode === 400
    && /not enough rights|need administrator|administrator rights|chat not found|not a member|have no rights|CHAT_WRITE_FORBIDDEN|CHAT_ADMIN_REQUIRED|CHANNEL_PRIVATE|bot was kicked/i
      .test(String(e.description || ''));
}

/**
 * Сотувчи канали пости матни (соф функция): сарлавҳа · нарх (бутун сўм) · тавсиф · дўкон ҳаволаси.
 * Телефон, исм, ҳудуд ЙЎҚ (40-банд). Лимитга сиғмаса фақат тавсиф қисқаради — ҳавола доим сақланади.
 */
function buildSellerCaption(clip, shopUrl) {
  const head = [];
  if (str(clip && clip.title, 180)) head.push(str(clip.title, 180));
  const price = clip && clip.price;
  if (Number.isInteger(price) && price > 0) head.push(page.formatMoneyUz(price));
  const tail = [];
  if (str(shopUrl, 300)) tail.push(`🛒 ${str(shopUrl, 300)}`);
  const fixed = head.concat(tail).join('\n');
  const room = CAPTION_MAX - fixed.length - 1;
  const desc = room > 40 ? str(clip && clip.description, Math.min(room, 600)) : '';
  const lines = desc ? head.concat([desc], tail) : head.concat(tail);
  return lines.join('\n').slice(0, CAPTION_MAX);
}

async function tgCall(token, method, params, timeout = 20000) {
  let res;
  try {
    res = await axios.post(`${TELEGRAM_API}/bot${token}/${method}`, params, { timeout });
  } catch (e) {
    // Хато объектида URL (токен билан) бор — фақат Telegram'нинг ўз матни олинади.
    const d = e && e.response && e.response.data;
    const code = (d && d.error_code) || (e && e.response && e.response.status) || 0;
    throw new TgError(code, str((d && d.description) || (e && e.code) || 'request failed', 200));
  }
  if (!res || !res.data || res.data.ok !== true) {
    const d = (res && res.data) || {};
    throw new TgError(d.error_code || 0, str(d.description || 'telegram error', 200));
  }
  return res.data.result;
}

/** Бот маълумоти (`getMe`) — инстанс ичида 1 соат кэш (ҳар карта очилишида Telegram'га бормаслик учун). */
function createBotInfo(db) {
  let cache = null;
  return async function botInfo() {
    const snap = await db.collection('settings').doc('tv_social').get();
    const s = telegramBotFromSettings(snap.exists ? snap.data() : {});
    if (!s.token) return { token: '', id: 0, username: '', channelId: s.channelId };
    if (cache && cache.token === s.token && Date.now() - cache.at < BOT_CACHE_MS) {
      return { ...cache.bot, token: s.token, channelId: s.channelId };
    }
    const me = await tgCall(s.token, 'getMe', {});
    const bot = { id: Number(me && me.id) || 0, username: str(me && me.username, 64) };
    cache = { token: s.token, at: Date.now(), bot };
    return { ...bot, token: s.token, channelId: s.channelId };
  };
}

/**
 * Клипни сотувчининг уланган каналига жойлаш (`tv_social_publish.js` чақиради). Хато — Error, `message` —
 * диагностика коди (клипнинг `socialPost.networks.seller_telegram.error`ига тушади, админ кўради).
 */
function createSellerChannelPoster({ db, admin, publicBase }) {
  const log = (o) => console.log(JSON.stringify({ module: 'seller_tg_channel', ...o }));
  const base = str(publicBase, 300);

  async function markNeedsReconnect(ownerPhone, chatId, errorCode) {
    const ref = db.collection(CHANNELS).doc(ownerPhone);
    await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const d = snap.exists ? (snap.data() || {}) : {};
      // Шу орада узилган/бошқа канал уланган бўлса — тегилмайди.
      if (d.status !== 'connected' || String(d.chatId) !== String(chatId)) return;
      t.update(ref, {
        status: 'needs_reconnect',
        lastErrorCode: errorCode,
        needsReconnectAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }

  return {
    async post(clip, videoUrl, token) {
      const started = Date.now();
      const owner = str(clip && clip.ownerPhone, 20);
      if (!/^\d{12}$/.test(owner)) throw new Error('SELLER_CHANNEL_NOT_CONNECTED');
      const [snap, shopSnap] = await Promise.all([
        db.collection(CHANNELS).doc(owner).get(),
        db.collection('tv_shops').doc(owner).get(),
      ]);
      const d = snap.exists ? (snap.data() || {}) : {};
      if (d.status === 'needs_reconnect') throw new Error('SELLER_CHANNEL_NEEDS_RECONNECT');
      if (d.status !== 'connected' || !str(d.chatId, 40)) throw new Error('SELLER_CHANNEL_NOT_CONNECTED');
      const idx = await db.collection(CHATS).doc(String(d.chatId)).get();
      if (!idx.exists || (idx.data() || {}).ownerPhone !== owner) throw new Error('SELLER_CHANNEL_NOT_CONNECTED');
      if (shopSnap.exists && (shopSnap.data() || {}).status === 'blocked') throw new Error('SHOP_BLOCKED');
      if (!token) throw new Error('TG_BOT_UNAVAILABLE');

      let link;
      try {
        link = await shopLinks.ensureOwnShopLink(db, admin, owner);
      } catch (e) {
        throw new Error(e && e.code === 'SHOP_BLOCKED' ? 'SHOP_BLOCKED' : 'SHOP_LINK_FAILED');
      }
      const shopUrl = base && link && link.publicId ? `${base}/s/${link.publicId}` : '';
      const caption = buildSellerCaption(clip, shopUrl);
      let msg;
      try {
        msg = await tgCall(token, 'sendVideo', {
          chat_id: String(d.chatId), video: videoUrl, caption, supports_streaming: true,
        }, 120000);
      } catch (e) {
        if (needsReconnectError(e)) {
          await markNeedsReconnect(owner, d.chatId, 'TG_RIGHTS_LOST');
          log({ action: 'post', clipId: clip.id, result: 'needs_reconnect', errorCode: 'TG_RIGHTS_LOST', durationMs: Date.now() - started });
          throw new Error(`SELLER_CHANNEL_NEEDS_RECONNECT: ${str(e.description, 160)}`);
        }
        log({ action: 'post', clipId: clip.id, result: 'error', errorCode: 'TG_SEND_FAILED', durationMs: Date.now() - started });
        throw new Error(`TG_SEND_FAILED: ${str(e.description || e.message, 160)}`);
      }
      const messageId = msg && msg.message_id;
      const username = str(d.username, 40);
      log({ action: 'post', clipId: clip.id, result: 'posted', durationMs: Date.now() - started });
      return {
        id: String(messageId || ''),
        url: username && messageId ? `https://t.me/${username}/${messageId}` : '',
      };
    },
  };
}

function attachSellerTgChannel(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid } = deps;
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code, message) => new HttpsError(status, message || code, { code });
  const log = (o) => console.log(JSON.stringify({ module: 'seller_tg_channel', ...o }));
  const botInfo = createBotInfo(db);
  const FV = admin.firestore.FieldValue;

  function requireUid(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length !== 12) throw new HttpsError('unauthenticated', 'Phone token required');
    return uid;
  }

  /** Сотувчи бўйича соатига RATE_MAX та чақирув (ҳар амал алоҳида; қатъий ойна, транзакция). */
  async function rateLimit(uid, action) {
    const ref = db.collection(RATE).doc(uid);
    const ok = await db.runTransaction(async (t) => {
      const s = await t.get(ref);
      const r = ((s.exists ? s.data() : {}) || {})[action] || {};
      const now = Date.now();
      const start = Number(r.start) || 0;
      const n = Number(r.n) || 0;
      if (now - start >= RATE_WINDOW_MS) {
        t.set(ref, { [action]: { start: now, n: 1 }, updatedAt: FV.serverTimestamp() }, { merge: true });
        return true;
      }
      if (n >= RATE_MAX) return false;
      t.set(ref, { [action]: { start, n: n + 1 }, updatedAt: FV.serverTimestamp() }, { merge: true });
      return true;
    });
    if (!ok) {
      log({ action, result: 'rate_limited', errorCode: 'SELLER_TG_RATE_LIMIT' });
      throw fail('resource-exhausted', 'SELLER_TG_RATE_LIMIT', 'Жуда кўп уриниш. Бир соатдан кейин қайта уриниб кўринг.');
    }
  }

  /** Telegram вақтинча ишламаяпти (429, 5xx, тармоқ узилиши) — «топилмади/админ эмас» деб адаштирмаслик учун. */
  const transientTg = (e) => e instanceof TgError && (e.tgCode === 0 || e.tgCode === 429 || e.tgCode >= 500);
  const tryLater = () => fail('unavailable', 'TG_TRY_LATER', 'Telegram ҳозир жавоб бермаяпти. Бироздан кейин уриниб кўринг.');

  async function requireBot() {
    let bot;
    try {
      bot = await botInfo();
    } catch (e) {
      log({ action: 'getMe', result: 'error', errorCode: 'TG_BOT_UNAVAILABLE', message: str(e && e.description, 120) });
      throw fail('unavailable', 'TG_BOT_UNAVAILABLE', 'Хизмат вақтинча ишламаяпти. Кейинроқ уриниб кўринг.');
    }
    if (!bot.token || !bot.id || !bot.username) {
      throw fail('unavailable', 'TG_BOT_UNAVAILABLE', 'Хизмат вақтинча ишламаяпти. Кейинроқ уриниб кўринг.');
    }
    return bot;
  }

  /** Бот каналда администратор ва «Хабар жойлаш» ҳуқуқи бор. */
  async function requireBotCanPost(bot, chatId) {
    let m;
    try {
      m = await tgCall(bot.token, 'getChatMember', { chat_id: chatId, user_id: bot.id });
    } catch (e) {
      if (transientTg(e)) throw tryLater();
      throw fail('failed-precondition', 'BOT_NOT_ADMIN', 'AVA боти каналда администратор эмас.');
    }
    const status = String((m && m.status) || '');
    if (status !== 'administrator' && status !== 'creator') {
      throw fail('failed-precondition', 'BOT_NOT_ADMIN', 'AVA боти каналда администратор эмас.');
    }
    if (status === 'administrator' && m.can_post_messages !== true) {
      throw fail('failed-precondition', 'BOT_NO_POST_RIGHT', 'Ботга «Хабар жойлаш» ҳуқуқини беринг.');
    }
  }

  async function getChat(bot, chatId) {
    try {
      return await tgCall(bot.token, 'getChat', { chat_id: chatId });
    } catch (e) {
      if (transientTg(e)) throw tryLater();
      throw fail('not-found', 'CHANNEL_NOT_FOUND', 'Канал топилмади. Номини текширинг.');
    }
  }

  const tsMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : 0);

  /** Иловага қайтадиган кўриниш (chatId ва бот токени йўқ). */
  function view(d, now = Date.now()) {
    const x = d || {};
    if (ACTIVE.includes(x.status)) {
      return { status: x.status, username: str(x.username, 40), title: str(x.title, 120) };
    }
    if (x.status === 'pending' && CODE_RE.test(String(x.code || '')) && tsMs(x.codeExpiresAt) > now) {
      return {
        status: 'pending', username: str(x.username, 40), title: str(x.title, 120),
        code: x.code, expiresAtMs: tsMs(x.codeExpiresAt),
      };
    }
    return { status: 'none' };
  }

  /** data: {} → { ok, available, botUsername, channel: { status, username?, title?, code?, expiresAtMs? } } */
  exportsObj.sellerTgChannelStatus = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    const snap = await db.collection(CHANNELS).doc(uid).get();
    let bot = { username: '' };
    try {
      bot = await botInfo();
    } catch (e) {
      log({ action: 'status', result: 'bot_error', errorCode: 'TG_BOT_UNAVAILABLE', message: str(e && e.description, 120) });
    }
    return {
      ok: true,
      available: Boolean(bot.username),
      botUsername: str(bot.username, 64),
      channel: view(snap.exists ? snap.data() : null),
    };
  });

  /**
   * 1-қадам. data: { username } → { ok, channel }. Канал ошкора, бот администратор + «Хабар жойлаш»; бошқа
   * сотувчига уланмаган. Код берилади (ўша канал учун амал қилаётган код бўлса — ўшаниси, 21-банд). Уланган канал
   * ҳуқуқни йўқотган (`needs_reconnect`) бўлса — эгалик аввал исботланган: ҳуқуқ текширилиб, код сўралмасдан тикланади.
   */
  exportsObj.sellerTgChannelPrepare = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUid(context);
    await rateLimit(uid, 'prepare');
    const parsed = parseChannelInput(data && data.username);
    if (parsed.private) {
      throw fail('invalid-argument', 'PRIVATE_CHANNEL_UNSUPPORTED', 'Фақат ошкора (@номли) канал уланади.');
    }
    if (!parsed.username) throw fail('invalid-argument', 'INVALID_USERNAME', 'Канал номини @nom кўринишида ёзинг.');
    const ownRef = db.collection(CHANNELS).doc(uid);
    const [own, shop] = await Promise.all([ownRef.get(), db.collection('tv_shops').doc(uid).get()]);
    if (shop.exists && (shop.data() || {}).status === 'blocked') {
      throw fail('failed-precondition', 'SHOP_BLOCKED', 'Дўконингиз вақтинча блокланган.');
    }
    const cur = own.exists ? (own.data() || {}) : {};
    if (ACTIVE.includes(cur.status) && str(cur.username, 40).toLowerCase() !== parsed.username.toLowerCase()) {
      throw fail('failed-precondition', 'SELLER_HAS_CHANNEL', 'Аввал уланган канални узинг.');
    }

    const bot = await requireBot();
    const chat = await getChat(bot, `@${parsed.username}`);
    if (!chat || chat.type !== 'channel') throw fail('failed-precondition', 'NOT_A_CHANNEL', 'Бу канал эмас.');
    if (!str(chat.username, 40)) {
      throw fail('invalid-argument', 'PRIVATE_CHANNEL_UNSUPPORTED', 'Фақат ошкора (@номли) канал уланади.');
    }
    const chatId = String(chat.id);
    const official = bot.channelId.replace(/^@/, '').toLowerCase();
    if (official && (official === chatId.toLowerCase() || official === str(chat.username, 40).toLowerCase())) {
      throw fail('permission-denied', 'CHANNEL_NOT_ALLOWED', 'Бу канални улаб бўлмайди.');
    }
    await requireBotCanPost(bot, chatId);

    const chatRef = db.collection(CHATS).doc(chatId);
    const out = await db.runTransaction(async (t) => {
      const [o, idx] = await Promise.all([t.get(ownRef), t.get(chatRef)]);
      const x = o.exists ? (o.data() || {}) : {};
      // Индекс бошқа сотувчида бўлса ҳам код берилади: уни канал тавсифига фақат ҲОЗИРГИ эгаси ёза олади (M3).
      const indexMine = idx.exists && (idx.data() || {}).ownerPhone === uid;
      const base = { username: str(chat.username, 40), title: str(chat.title, 120), updatedAt: FV.serverTimestamp() };
      if (ACTIVE.includes(x.status) && String(x.chatId) !== chatId) {
        throw fail('failed-precondition', 'SELLER_HAS_CHANNEL', 'Аввал уланган канални узинг.');
      }
      // Кодсиз тиклаш — фақат индекс ҳали шу сотувчида (эгалик аввал исботланган ва бошқага ўтмаган).
      if (ACTIVE.includes(x.status) && indexMine) {
        t.set(ownRef, {
          ...base, status: 'connected', verifiedAt: FV.serverTimestamp(), lastErrorCode: FV.delete(),
        }, { merge: true });
        return { result: x.status === 'connected' ? 'already_connected' : 'reconnected', channel: { ...base, status: 'connected' } };
      }
      const now = Date.now();
      if (x.status === 'pending' && String(x.chatId) === chatId && CODE_RE.test(String(x.code || ''))
          && tsMs(x.codeExpiresAt) > now) {
        return { result: 'pending_existing', channel: { ...base, status: 'pending', code: x.code, expiresAtMs: tsMs(x.codeExpiresAt) } };
      }
      const code = newCode();
      const exp = admin.firestore.Timestamp.fromMillis(now + CODE_TTL_MS);
      t.set(ownRef, {
        ...base, ownerPhone: uid, status: 'pending', chatId, code, codeExpiresAt: exp, codeIssuedAt: FV.serverTimestamp(),
      }, { merge: true });
      return { result: 'pending_new', channel: { ...base, status: 'pending', code, expiresAtMs: exp.toMillis() } };
    });
    log({ action: 'prepare', result: out.result, durationMs: Date.now() - started });
    const c = out.channel;
    return {
      ok: true,
      channel: c.status === 'pending'
        ? { status: 'pending', username: c.username, title: c.title, code: c.code, expiresAtMs: c.expiresAtMs }
        : { status: 'connected', username: c.username, title: c.title },
    };
  });

  /** 2-қадам. data: {} → { ok, channel }. Код канал тавсифида бўлса — уланади (бир канал = бир сотувчи, транзакция). */
  exportsObj.sellerTgChannelConnect = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUid(context);
    await rateLimit(uid, 'connect');
    const ownRef = db.collection(CHANNELS).doc(uid);
    const own = await ownRef.get();
    const cur = own.exists ? (own.data() || {}) : {};
    if (cur.status === 'connected') {
      return { ok: true, channel: { status: 'connected', username: str(cur.username, 40), title: str(cur.title, 120) } };
    }
    if (cur.status !== 'pending' || !CODE_RE.test(String(cur.code || '')) || !str(cur.chatId, 40)) {
      throw fail('failed-precondition', 'NO_PENDING_CODE', 'Аввал канал номини киритиб, код олинг.');
    }
    if (tsMs(cur.codeExpiresAt) <= Date.now()) {
      throw fail('deadline-exceeded', 'CODE_EXPIRED', 'Код муддати тугади. Янги код олинг.');
    }
    const chatId = String(cur.chatId);
    const chatRef = db.collection(CHATS).doc(chatId);
    const bot = await requireBot();
    const chat = await getChat(bot, chatId);
    if (!descriptionHasCode(chat && chat.description, cur.code)) {
      log({ action: 'connect', result: 'code_not_found', errorCode: 'CODE_NOT_FOUND', durationMs: Date.now() - started });
      throw fail('failed-precondition', 'CODE_NOT_FOUND', 'Код канал тавсифида топилмади.');
    }
    await requireBotCanPost(bot, chatId);

    const out = await db.runTransaction(async (t) => {
      const [o, idx] = await Promise.all([t.get(ownRef), t.get(chatRef)]);
      const x = o.exists ? (o.data() || {}) : {};
      if (x.status === 'connected' && String(x.chatId) === chatId) return { result: 'already_connected', x };
      if (x.status !== 'pending' || x.code !== cur.code || String(x.chatId) !== chatId) {
        throw fail('aborted', 'CONNECT_STATE_CHANGED', 'Қайта уриниб кўринг.');
      }
      // Индекс бошқа сотувчида — код ҲОЗИР тавсифда: эгалик ЎТАДИ (M3). Эскиси узилади (ҳужжати қолади).
      const prevOwner = idx.exists ? str((idx.data() || {}).ownerPhone, 20) : '';
      let transferred = '';
      if (prevOwner && prevOwner !== uid) {
        const prevRef = db.collection(CHANNELS).doc(prevOwner);
        const prev = await t.get(prevRef);
        const px = prev.exists ? (prev.data() || {}) : {};
        if (prev.exists && String(px.chatId) === chatId && ACTIVE.includes(px.status)) {
          t.set(prevRef, {
            status: 'disconnected', lastErrorCode: 'CHANNEL_TRANSFERRED',
            disconnectedAt: FV.serverTimestamp(), updatedAt: FV.serverTimestamp(),
          }, { merge: true });
        }
        transferred = 'transferred';
      }
      t.set(chatRef, { ownerPhone: uid, chatId, connectedAt: FV.serverTimestamp() });
      const patch = {
        status: 'connected',
        username: str(chat.username, 40) || str(x.username, 40),
        title: str(chat.title, 120) || str(x.title, 120),
        connectedAt: FV.serverTimestamp(),
        verifiedAt: FV.serverTimestamp(),
        updatedAt: FV.serverTimestamp(),
        code: FV.delete(),
        codeExpiresAt: FV.delete(),
        lastErrorCode: FV.delete(),
      };
      t.set(ownRef, patch, { merge: true });
      return { result: transferred || 'connected', x: { ...x, ...patch } };
    });
    log({ action: 'connect', result: out.result, durationMs: Date.now() - started });
    return { ok: true, channel: { status: 'connected', username: str(out.x.username, 40), title: str(out.x.title, 120) } };
  });

  /** data: {} → { ok, channel: { status: 'none' } }. Такрор чақирилса — ўша натижа. */
  exportsObj.sellerTgChannelDisconnect = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = requireUid(context);
    const ownRef = db.collection(CHANNELS).doc(uid);
    const result = await db.runTransaction(async (t) => {
      const o = await t.get(ownRef);
      const x = o.exists ? (o.data() || {}) : {};
      if (!o.exists || !['pending', ...ACTIVE].includes(x.status)) return 'noop';
      let idx = null;
      const chatId = str(x.chatId, 40);
      if (chatId) idx = await t.get(db.collection(CHATS).doc(chatId));
      if (idx && idx.exists && (idx.data() || {}).ownerPhone === uid) t.delete(idx.ref);
      t.set(ownRef, {
        status: 'disconnected',
        disconnectedAt: FV.serverTimestamp(),
        updatedAt: FV.serverTimestamp(),
        code: FV.delete(),
        codeExpiresAt: FV.delete(),
      }, { merge: true });
      return 'disconnected';
    });
    log({ action: 'disconnect', result, durationMs: Date.now() - started });
    return { ok: true, channel: { status: 'none' } };
  });
}

module.exports = {
  attachSellerTgChannel,
  createSellerChannelPoster,
  telegramBotFromSettings,
  parseChannelInput,
  descriptionHasCode,
  buildSellerCaption,
  needsReconnectError,
  newCode,
  TgError,
  NET,
  CHANNELS,
  CHATS,
  RATE,
  RATE_MAX,
};
