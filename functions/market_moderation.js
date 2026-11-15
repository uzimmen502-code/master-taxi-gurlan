/**
 * «Бозорлар» 2a-босқич (эга 2026-11-15): олдиндан модерация ва 30 кунлик муддат.
 *
 * Эга қарорлари (CONFIRMED, 2026-11-15):
 *   1. Муддат тугаса → `status: 'expired'` (бозордан яширинади, сотувчида қолади; янгилаш → `pending`). Ўчирилмайди.
 *   2. 30 кун ФАҚАТ: tv_shop_items, realty_listings, ads (type == 'cheap_product'). wholesale_products — муддатсиз.
 *   3. Мавжуд фаол эълонлар — `tools/migrate_market_expiry.js` (deploy санаси + 30 кун) + огоҳлантириш.
 *   4. Эга контентни таҳрирласа (CONTENT_FIELDS) `active`/`expired` → `pending`. Ўчириш (`deleted`) — модерациясиз.
 *   6. Барча бозорларда олдиндан модерация. `settings/app.tvAutoApprove`га (AVAGram клиплари) тегилмайди.
 *
 * Компонентлар:
 *   - `onShopItemModeration` (tv_shop_items onWrite): янги → `pending`; эга контент таҳрири → `pending`;
 *     админ бошқа йўл билан `active` қилганда (`tv_clips_moderation_screen`, `adminUpdateBusinessProduct`) муддат йўқ
 *     бўлса — `expiresAt` = +30 кун. Ўз ёзувларини ва админ таҳририни (moderatedAt / admin_audit) ўтказиб юборади.
 *   - `adminModerateListing` — approve/reject, транзакция + `admin_audit` (kind `listing_moderation`).
 *   - `renewMarketListing` — эга: `expired → pending` (ads: муддати ўзи тугаган `inactive` → `pending`).
 *   - `marketListingsExpirySweep` (ҳар соат :10) — `active` + `expiresAt <= now` → `expired`.
 *   - `marketListingsExpiryWarning` (ҳар куни 10:00) — 24 соат ичида тугайдиганларга огоҳлантириш.
 *
 * МУҲИМ — эски (жонли) функциялар билан мослик (INFERRED/CONFIRMED коддан, 2026-11-15):
 *   - `realtyExpirySweep` (жонли манба 2026-09-28, main'дан ФАРҚЛИ — шунинг учун ўзгартирилмади) ҳар куни 00:20
 *     `expiresAt <= now` бўлган ҲАР ҚАНДАЙ realty ҳужжатини ЎЧИРАДИ. Шунинг учун бу ерда муддати тугаган ҳужжатдан
 *     `expiresAt` олиб ташланади (эски қиймат `expiresAtPrev`да) — эски сўров уни топмайди. Кўчмас мулк учун
 *     15 дақиқа олдиндан (`REALTY_DELETE_GUARD_MS`) — 00:10 даги ўтиш 00:20 гачагиларни ҳам қамрайди.
 *     `pending`/`blocked` ҳужжатлар ҳам ўчмасин деб уларда ҳам `expiresAt` олиб ташланади (статус ўзгармайди).
 *   - ads (cheap_product) муддати — `expirePendingTrips` (ҳар дақиқа) `inactive` + `autoExpiredAt` қилади ва
 *     `onAdUpdate` сотувчига хабар юборади. Бу мавжуд «expired» эквиваленти; бу ерда ads супурилмайди (пойга бўлмасин).
 *     ads approve/reject хабарини ҳам `onAdUpdate` юборади — бу ерда иккинчи push юборилмайди.
 */
'use strict';

const { stableStringify } = require('./market_taxonomy');
const { normalizeLang, langOfPhone } = require('./notif_i18n');

const MODULE = 'market_moderation';
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const ADMIN_AUDIT = 'admin_audit';
const AUDIT_KIND = 'listing_moderation';

const EXPIRY_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;
const REASON_MAX = 300;
const PAGE = 400;
const MAX_ROUNDS = 25;
const REALTY_DELETE_GUARD_MS = 15 * 60 * 1000;

const COLLECTIONS = Object.freeze(['tv_shop_items', 'wholesale_products', 'realty_listings', 'ads']);
/** Муддатли коллекциялар (эга қарори 2). */
const EXPIRING = Object.freeze(['tv_shop_items', 'realty_listings', 'ads']);
/** Эга таҳрирлаганда қайта модерацияга тушадиган майдонлар (эга қарори 4). */
const CONTENT_FIELDS = Object.freeze([
  'title', 'photoUrls', 'photoUrl', 'description', 'price', 'priceUnit', 'market', 'category', 'attrs', 'imported',
]);
/** Контент таҳририда `pending`га қайтадиган ҳолатлар (эга қарори 4: active/expired). */
const EDIT_RESUBMIT_STATUSES = Object.freeze(['active', 'expired']);

/** Рад этилганда қайси статус (мавжуд луғат). */
const REJECT_STATUS = Object.freeze({
  tv_shop_items: 'rejected', // янги қиймат (бу коллекцияда аввал рад этиш йўқ эди)
  wholesale_products: 'inactive', // admin панелнинг мавжуд қиймати
  realty_listings: 'blocked', // adminSetRealtyStatus: active|pending|blocked
  ads: 'inactive', // adminUpdateMarketAdStatus: inactive + adminRejected
});

const MESSAGES = Object.freeze({
  listing_approved: {
    uz_Cyrl: { title: '✅ Эълонингиз тасдиқланди', body: '«{title}» бозорда кўринади. Муддати — 30 кун.' },
    uz_Latn: { title: '✅ E\'loningiz tasdiqlandi', body: '«{title}» bozorda ko\'rinadi. Muddati — 30 kun.' },
    ru: { title: '✅ Объявление одобрено', body: '«{title}» опубликовано на рынке. Срок — 30 дней.' },
  },
  listing_rejected: {
    uz_Cyrl: { title: '⛔ Эълон қабул қилинмади', body: '«{title}»: {reason}' },
    uz_Latn: { title: '⛔ E\'lon qabul qilinmadi', body: '«{title}»: {reason}' },
    ru: { title: '⛔ Объявление отклонено', body: '«{title}»: {reason}' },
  },
  listing_expired: {
    uz_Cyrl: { title: '⏳ Эълон муддати тугади', body: '«{title}» бозордан олинди. Янгилаш учун эълонингизни очинг.' },
    uz_Latn: { title: '⏳ E\'lon muddati tugadi', body: '«{title}» bozordan olindi. Yangilash uchun e\'loningizni oching.' },
    ru: { title: '⏳ Срок объявления истёк', body: '«{title}» снято с рынка. Откройте объявление, чтобы продлить.' },
  },
  listing_expiry_warning: {
    uz_Cyrl: { title: '⏳ Эълон муддати тугаяпти', body: '«{title}» эртага бозордан олинади. Кейин уни янгилашингиз мумкин.' },
    uz_Latn: { title: '⏳ E\'lon muddati tugayapti', body: '«{title}» ertaga bozordan olinadi. Keyin uni yangilashingiz mumkin.' },
    ru: { title: '⏳ Срок объявления заканчивается', body: '«{title}» завтра будет снято с рынка. Потом его можно продлить.' },
  },
});

function renderMessage(key, lang, params = {}) {
  const t = MESSAGES[key][normalizeLang(lang)];
  const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => (params[k] === undefined ? '' : String(params[k])));
  return { title: fill(t.title), body: fill(t.body) };
}

// ───────────────────────── Тоза ёрдамчилар (тестланади) ─────────────────────────

const digitsOf = (v) => String(v == null ? '' : v).replace(/\D/g, '');
function canonPhone(v) {
  const d = digitsOf(v);
  return d.length === 9 ? `998${d}` : d;
}
function samePhone(a, b) {
  const x = canonPhone(a);
  return x.length >= 12 && x === canonPhone(b);
}

function millisOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'number') return v;
  return null;
}
function tsChanged(a, b) {
  return millisOf(a) !== millisOf(b);
}

/** Контент майдонларидан бирортаси ўзгардими (майдонни ўчириш ҳам ўзгариш; калит тартиби аҳамиятсиз). */
function contentChanged(before, after) {
  const b = before || {};
  const a = after || {};
  return CONTENT_FIELDS.some((k) => stableStringify(b[k]) !== stableStringify(a[k]));
}

/** Янги ҳужжат: `active`/`pending`/статуссиз → `pending` (submittedAt билан). Бошқа ҳолат (масалан, `deleted`) — тегилмайди. */
function nextStatusOnCreate(data) {
  const d = data || {};
  if (d.submittedAt) return null; // аллақачон ишланган
  const st = d.status === undefined ? 'active' : d.status;
  return st === 'active' || st === 'pending' ? 'pending' : null;
}

/** `now`дан 30 кун кейинги сана. */
function expiryDate(nowMs) {
  return new Date((nowMs == null ? Date.now() : nowMs) + EXPIRY_DAYS * DAY_MS);
}

/**
 * Триггер режаси (тоза): `{ kind }` ёки null.
 *   create_pending — янги ҳужжат модерацияга;
 *   edit_pending   — эга active/expired ҳужжат контентини ўзгартирди;
 *   activate_stamp — ҳужжат `active`га ўтди, лекин яроқли `expiresAt` йўқ.
 */
function planShopItemWrite(before, after, nowMs) {
  if (!after) return null;
  if (!before) {
    // `ownerPhone`сиз ҳужжат — мижоз яратмаган (масалан, `tv_social_publish` merge'и) — тегилмайди.
    if (!digitsOf(after.ownerPhone)) return null;
    return nextStatusOnCreate(after) ? { kind: 'create_pending' } : null;
  }
  if (before.status === after.status
      && EDIT_RESUBMIT_STATUSES.includes(after.status)
      && contentChanged(before, after)
      && !tsChanged(before.moderatedAt, after.moderatedAt)) {
    return { kind: 'edit_pending', fromStatus: after.status };
  }
  if (after.status === 'active' && before.status !== 'active') {
    const exp = millisOf(after.expiresAt);
    if (exp == null || exp <= nowMs) return { kind: 'activate_stamp' };
  }
  return null;
}

/** Рад этиш сабаби: 1..300 белги, акс ҳолда null. */
function normalizeReason(v) {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length >= 1 && s.length <= REASON_MAX ? s : null;
}

/**
 * Модерация патчи (тоза). `fv` — { ts(), del(), at(ms) } фабрикаси (тестда оддий қийматлар).
 */
function buildModerationPatch(collection, decision, { cur, actor, reason, nowMs, fv }) {
  const c = cur || {};
  const base = { moderatedAt: fv.ts(), moderatedBy: actor };
  if (decision === 'approve') {
    const p = { ...base, status: 'active', rejectReason: fv.del() };
    if (collection === 'tv_shop_items') {
      Object.assign(p, {
        expiresAt: fv.at(expiryDate(nowMs).getTime()),
        expiryWarnedAt: fv.del(), expiryWarnedFor: fv.del(), expiresAtPrev: fv.del(), expiredAt: fv.del(),
      });
    } else if (collection === 'wholesale_products') {
      Object.assign(p, { publishedAt: fv.ts(), updatedAt: fv.ts() });
    } else if (collection === 'realty_listings') {
      // Пуллик даража (РЕКЛАМА/СРОЧНО) муддати узунроқ бўлса — объект умри шу (эга қарори 2026-10-02).
      let expMs = expiryDate(nowMs).getTime();
      const tierUntil = millisOf(c.tierUntil);
      if (c.tier && c.tier !== 'plain' && tierUntil && tierUntil > expMs) expMs = tierUntil;
      Object.assign(p, {
        expiresAt: fv.at(expMs), expiryWarnedAt: fv.del(), expiresAtPrev: fv.del(), expiredAt: fv.del(), updatedAt: fv.ts(),
      });
    } else if (collection === 'ads') {
      Object.assign(p, {
        publishedAt: fv.ts(), expiresAt: fv.at(expiryDate(nowMs).getTime()), adminRejected: false,
        expiryWarnedAt: fv.del(), expiryWarnedFor: fv.del(), updatedAt: fv.ts(),
      });
    }
    return p;
  }
  const p = { ...base, status: REJECT_STATUS[collection], rejectReason: reason, rejectedAt: fv.ts() };
  if (collection !== 'tv_shop_items') {
    p.adminNote = reason; // мавжуд UI шу майдонни кўрсатади
    p.updatedAt = fv.ts();
  }
  if (collection === 'ads') p.adminRejected = true;
  return p;
}

/**
 * Муддат супуриш режаси (тоза): `{ patch, notify }`. `expiresAt <= cutoff` бўлган ҲАР ҳужжат учун патч
 * қайтарилади (aks holda sahifalash to'xtab qolardi): `active` → `expired`; бошқалари — фақат `expiresAt` олинади.
 */
function planExpiry(collection, data, fv) {
  const d = data || {};
  const keep = { expiresAt: fv.del(), expiresAtPrev: d.expiresAt == null ? null : d.expiresAt };
  if (d.status === 'active') {
    const patch = { ...keep, status: 'expired', expiredAt: fv.ts() };
    if (collection === 'realty_listings') patch.updatedAt = fv.ts();
    return { patch, notify: true };
  }
  return { patch: keep, notify: false };
}

/** Огоҳлантириш керакми (тоза): active, муддат (now, now+24h] ичида, шу муддат учун ҳали огоҳлантирилмаган. */
function needsExpiryWarning(data, nowMs) {
  const d = data || {};
  if (d.status !== 'active') return false;
  const exp = millisOf(d.expiresAt);
  if (exp == null || exp <= nowMs || exp > nowMs + DAY_MS) return false;
  return millisOf(d.expiryWarnedFor) !== exp;
}

function screenOf(collection) {
  if (collection === 'realty_listings') return 'realty_my';
  if (collection === 'ads') return 'my_ads';
  return 'news';
}

// ───────────────────────── Firebase қисми ─────────────────────────

function attachMarketModeration(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const fv = {
    ts: () => FV.serverTimestamp(),
    del: () => FV.delete(),
    at: (ms) => admin.firestore.Timestamp.fromMillis(ms),
  };
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: MODULE, ...fields }));

  function callerUid(context) {
    if (!context || !context.auth) throw fail('unauthenticated', 'AUTH_REQUIRED');
    const raw = (context.auth.token && context.auth.token.phone_number) || '';
    const uid = canonPhone(raw);
    if (uid.length < 12) throw fail('unauthenticated', 'PHONE_REQUIRED');
    return uid;
  }

  function parseTarget(data) {
    const d = data || {};
    const collection = String(d.collection || '');
    if (!COLLECTIONS.includes(collection)) throw fail('invalid-argument', 'COLLECTION_INVALID');
    const id = typeof d.id === 'string' ? d.id.trim() : '';
    if (!id || id.length > 128 || id.includes('/')) throw fail('invalid-argument', 'ID_INVALID');
    return { collection, id, ref: db.collection(collection).doc(id) };
  }

  /** Эълон эгасининг телефони (хабар учун). realty — ёпиқ `private/detail.ownerId`. */
  async function ownerPhoneOf(collection, ref, data) {
    const d = data || {};
    if (collection === 'tv_shop_items') return canonPhone(d.ownerPhone);
    if (collection === 'wholesale_products') return canonPhone(d.sellerId);
    if (collection === 'ads') return canonPhone(d.ownerId);
    try {
      const priv = await ref.collection('private').doc('detail').get();
      return canonPhone((priv.data() || {}).ownerId);
    } catch (e) {
      return '';
    }
  }

  async function notify(collection, id, phone, key, params, dataType) {
    if (!phone || phone.length < 12) return false;
    try {
      const lang = await langOfPhone(db, phone);
      const { title, body } = renderMessage(key, lang, params);
      await notifyUserInApp({
        userId: phone, title, body, category: 'info', source: 'listing_moderation', dataType,
        screen: screenOf(collection), extraData: { collection, listingId: String(id) },
      });
      return true;
    } catch (e) {
      log({ action: 'notify', collection, listingId: id, result: 'error', errorCode: 'NOTIFY_FAILED', error: String(e.message || e) });
      return false;
    }
  }

  const titleOf = (d) => String((d && d.title) || '').trim().slice(0, 60);

  // ── 1. Триггер ──
  exportsObj.onShopItemModeration = functions.firestore
    .document('tv_shop_items/{itemId}')
    .onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const before = change.before.exists ? (change.before.data() || {}) : null;
      const after = change.after.data() || {};
      const plan = planShopItemWrite(before, after, Date.now());
      if (!plan) return null;
      const itemId = context.params.itemId;
      const ref = change.after.ref;

      // Админ CF таҳрири (`adminUpdateBusinessProduct`): ўша транзакцияда admin_audit ёзади, `at` == `updatedAt`.
      if (plan.kind === 'edit_pending' && after.updatedBy && tsChanged(before.updatedAt, after.updatedAt)) {
        const audits = await db.collection(ADMIN_AUDIT)
          .where('target', '==', itemId).where('kind', '==', 'business_product_update').get();
        const ua = millisOf(after.updatedAt);
        if (audits.docs.some((a) => millisOf((a.data() || {}).at) === ua)) {
          log({ action: 'onShopItemModeration', itemId, result: 'skip_admin_edit' });
          return null;
        }
      }

      const outcome = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) return 'gone';
        const cur = snap.data() || {};
        if (plan.kind === 'create_pending') {
          if (!nextStatusOnCreate(cur)) return 'noop';
          t.update(ref, { status: 'pending', submittedAt: fv.ts(), moderationReason: 'new' });
          return 'pending';
        }
        if (plan.kind === 'edit_pending') {
          // Орада модерация бўлмаган ва ҳолат ўзгармаган бўлса (кейинги ёзув таҳрирни «яшира» олмасин).
          if (cur.status !== plan.fromStatus || tsChanged(cur.moderatedAt, after.moderatedAt)) return 'noop';
          t.update(ref, {
            status: 'pending', submittedAt: fv.ts(), moderationReason: 'owner_edit', rejectReason: fv.del(),
          });
          return 'pending';
        }
        // activate_stamp
        const exp = millisOf(cur.expiresAt);
        if (cur.status !== 'active' || (exp != null && exp > Date.now())) return 'noop';
        t.update(ref, {
          expiresAt: fv.at(expiryDate(Date.now()).getTime()),
          expiryWarnedAt: fv.del(), expiryWarnedFor: fv.del(), expiresAtPrev: fv.del(),
        });
        return 'stamped';
      });
      log({ action: 'onShopItemModeration', itemId, plan: plan.kind, result: outcome });
      return null;
    });

  // ── 2. Админ модерацияси ──
  exportsObj.adminModerateListing = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const { collection, id, ref } = parseTarget(data);
    const decision = String((data && data.decision) || '');
    if (decision !== 'approve' && decision !== 'reject') throw fail('invalid-argument', 'DECISION_INVALID');
    let reason = null;
    if (decision === 'reject') {
      reason = normalizeReason(data && data.reason);
      if (!reason) throw fail('invalid-argument', 'REASON_REQUIRED');
    }
    let result;
    try {
      result = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) throw fail('not-found', 'LISTING_NOT_FOUND');
        const cur = snap.data() || {};
        if (collection === 'ads' && cur.type !== 'cheap_product') throw fail('invalid-argument', 'COLLECTION_INVALID');
        if (cur.status !== 'pending') throw fail('failed-precondition', 'LISTING_NOT_PENDING', { status: String(cur.status || '') });
        const patch = buildModerationPatch(collection, decision, { cur, actor, reason, nowMs: Date.now(), fv });
        t.update(ref, patch);
        t.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: AUDIT_KIND, collection, id, target: id, decision, actor, at: fv.ts(),
          previousStatus: 'pending', nextStatus: patch.status, ...(reason ? { reason } : {}),
        });
        return { cur, nextStatus: patch.status, expiresAt: patch.expiresAt ? millisOf(patch.expiresAt) : null };
      });
    } catch (e) {
      const code = (e && e.details && e.details.code) || 'INTERNAL';
      log({ action: 'adminModerateListing', collection, listingId: id, userId: actor, decision, result: 'error', errorCode: code, duration: Date.now() - started });
      if (e instanceof HttpsError) throw e;
      throw fail('internal', 'MODERATION_WRITE_FAILED');
    }
    // ads хабарини `onAdUpdate` юборади (иккинчи push бўлмасин).
    let notified = false;
    if (collection !== 'ads') {
      const phone = await ownerPhoneOf(collection, ref, result.cur);
      notified = decision === 'approve'
        ? await notify(collection, id, phone, 'listing_approved', { title: titleOf(result.cur) }, 'listing_approved')
        : await notify(collection, id, phone, 'listing_rejected', { title: titleOf(result.cur), reason }, 'listing_rejected');
    }
    log({ action: 'adminModerateListing', collection, listingId: id, userId: actor, decision, result: 'ok', status: result.nextStatus, notified, duration: Date.now() - started });
    return { ok: true, collection, id, status: result.nextStatus, expiresAt: result.expiresAt };
  });

  // ── 3. Эга: янгилаш ──
  async function isOwner(collection, ref, cur, uid) {
    if (collection === 'tv_shop_items') return samePhone(cur.ownerPhone, uid);
    if (collection === 'ads') return samePhone(cur.ownerId, uid);
    // realty: компания калити (`users/{uid}.realtyOwnerKey`) ёки ёпиқ ҳужжатдаги эга рақами.
    const key = String(cur.ownerKey || '');
    if (key) {
      const u = await db.collection('users').doc(uid).get();
      if (String((u.data() || {}).realtyOwnerKey || '') === key) return true;
    }
    const priv = await ref.collection('private').doc('detail').get();
    return samePhone((priv.data() || {}).ownerId, uid);
  }

  exportsObj.renewMarketListing = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const uid = callerUid(context);
    const { collection, id, ref } = parseTarget(data);
    if (!EXPIRING.includes(collection)) throw fail('invalid-argument', 'COLLECTION_INVALID');
    const pre = await ref.get();
    if (!pre.exists) throw fail('not-found', 'LISTING_NOT_FOUND');
    if (collection === 'ads' && (pre.data() || {}).type !== 'cheap_product') throw fail('invalid-argument', 'COLLECTION_INVALID');
    if (!(await isOwner(collection, ref, pre.data() || {}, uid))) {
      log({ action: 'renewMarketListing', collection, listingId: id, userId: uid, result: 'error', errorCode: 'NOT_OWNER' });
      throw fail('permission-denied', 'NOT_OWNER');
    }
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('not-found', 'LISTING_NOT_FOUND');
      const cur = snap.data() || {};
      if (cur.status === 'pending') return { changed: false };
      const renewable = collection === 'ads'
        ? (cur.status === 'inactive' && !!cur.autoExpiredAt && cur.adminRejected !== true)
        : cur.status === 'expired';
      if (!renewable) throw fail('failed-precondition', 'LISTING_NOT_EXPIRED', { status: String(cur.status || '') });
      const patch = collection === 'ads'
        // ads: `onAdUpdate` (`inactive → pending`) кутиш муддатини ўзи ёзади.
        ? { status: 'pending', updatedAt: fv.ts() }
        : { status: 'pending', submittedAt: fv.ts(), moderationReason: 'renew', renewedAt: fv.ts() };
      if (collection === 'realty_listings') patch.updatedAt = fv.ts();
      t.update(ref, patch);
      return { changed: true };
    });
    log({ action: 'renewMarketListing', collection, listingId: id, userId: uid, result: 'ok', changed: out.changed, duration: Date.now() - started });
    return { ok: true, status: 'pending', ...out };
  });

  // ── 4. Муддат супуриш ──
  async function commitPage(collection, docs, plans) {
    const batch = db.batch();
    docs.forEach((doc, i) => batch.update(doc.ref, plans[i].patch, { lastUpdateTime: doc.updateTime }));
    try {
      await batch.commit();
      return docs.map(() => true);
    } catch (e) {
      // Орада ўзгарган ҳужжат(лар) бор — ҳар бирини транзакцияда қайта текшириб ёзамиз.
      log({ action: 'marketListingsExpirySweep', collection, result: 'batch_retry', error: String(e.message || e) });
      const done = [];
      for (let i = 0; i < docs.length; i += 1) {
        try {
          done.push(await db.runTransaction(async (t) => {
            const s = await t.get(docs[i].ref);
            if (!s.exists) return false;
            const cur = s.data() || {};
            const exp = millisOf(cur.expiresAt);
            if (exp == null || exp > millisOf(docs[i].data().expiresAt)) return false;
            const plan = planExpiry(collection, cur, fv);
            t.update(docs[i].ref, plan.patch);
            plans[i] = plan;
            return true;
          }));
        } catch (e2) {
          done.push(false);
        }
      }
      return done;
    }
  }

  async function sweepCollection(collection, cutoffMs) {
    const stats = { expired: 0, stripped: 0, notified: 0 };
    const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMs);
    for (let round = 0; round < MAX_ROUNDS; round += 1) {
      const snap = await db.collection(collection)
        .where('expiresAt', '<=', cutoff).orderBy('expiresAt').limit(PAGE).get();
      if (snap.empty) break;
      const plans = snap.docs.map((doc) => planExpiry(collection, doc.data(), fv));
      const done = await commitPage(collection, snap.docs, plans);
      for (let i = 0; i < snap.docs.length; i += 1) {
        if (!done[i]) continue;
        if (!plans[i].notify) { stats.stripped += 1; continue; }
        stats.expired += 1;
        const d = snap.docs[i].data();
        const phone = await ownerPhoneOf(collection, snap.docs[i].ref, d);
        if (await notify(collection, snap.docs[i].id, phone, 'listing_expired', { title: titleOf(d) }, 'listing_expired')) {
          stats.notified += 1;
        }
      }
      if (snap.size < PAGE) break;
    }
    return stats;
  }

  async function runExpirySweep(nowMs = Date.now()) {
    const out = {};
    out.tv_shop_items = await sweepCollection('tv_shop_items', nowMs);
    // realty: эски `realtyExpirySweep` (00:20) ўчирмасин — 15 дақиқа олдиндан.
    out.realty_listings = await sweepCollection('realty_listings', nowMs + REALTY_DELETE_GUARD_MS);
    return out;
  }

  exportsObj.marketListingsExpirySweep = functions
    .runWith({ timeoutSeconds: 540 })
    .pubsub.schedule('10 * * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const started = Date.now();
      const stats = await runExpirySweep(started);
      log({ action: 'marketListingsExpirySweep', result: 'ok', stats, duration: Date.now() - started });
      return null;
    });

  // ── 5. Огоҳлантириш (realty — мавжуд `realtyExpiryWarning`, `expiryWarnedAt`; бу ерда йўқ) ──
  async function warnQuery(collection, query, nowMs) {
    let sent = 0;
    let last = null;
    for (let round = 0; round < MAX_ROUNDS; round += 1) {
      let q = query.orderBy('expiresAt').limit(PAGE);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        if (collection === 'ads' && d.type !== 'cheap_product') continue;
        if (!needsExpiryWarning(d, nowMs)) continue;
        try {
          // Аввал белги (транзакция) — қайта ишга тушса иккинчи хабар кетмасин.
          const claimed = await db.runTransaction(async (t) => {
            const s = await t.get(doc.ref);
            if (!s.exists || !needsExpiryWarning(s.data(), nowMs)) return false;
            t.update(doc.ref, { expiryWarnedAt: fv.ts(), expiryWarnedFor: s.data().expiresAt });
            return true;
          });
          if (!claimed) continue;
          const phone = await ownerPhoneOf(collection, doc.ref, d);
          if (await notify(collection, doc.id, phone, 'listing_expiry_warning', { title: titleOf(d) }, 'listing_expiry_warning')) sent += 1;
        } catch (e) {
          log({ action: 'marketListingsExpiryWarning', collection, listingId: doc.id, result: 'error', errorCode: 'WARN_FAILED', error: String(e.message || e) });
        }
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < PAGE) break;
    }
    return sent;
  }

  async function runExpiryWarning(nowMs = Date.now()) {
    const from = admin.firestore.Timestamp.fromMillis(nowMs);
    const to = admin.firestore.Timestamp.fromMillis(nowMs + DAY_MS);
    const tv = await warnQuery('tv_shop_items', db.collection('tv_shop_items')
      .where('expiresAt', '>', from).where('expiresAt', '<=', to), nowMs);
    // ads: мавжуд (status, expiresAt) индекси (`expirePendingTrips`); тур хотирада филтрланади.
    const ads = await warnQuery('ads', db.collection('ads').where('status', '==', 'active')
      .where('expiresAt', '>', from).where('expiresAt', '<=', to), nowMs);
    return { tv_shop_items: tv, ads };
  }

  exportsObj.marketListingsExpiryWarning = functions
    .runWith({ timeoutSeconds: 540 })
    .pubsub.schedule('0 10 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const started = Date.now();
      const sent = await runExpiryWarning(started);
      log({ action: 'marketListingsExpiryWarning', result: 'ok', sent, duration: Date.now() - started });
      return null;
    });

  // Тестлар учун (эмулятор): жадвални кутмасдан ишга тушириш.
  return { runExpirySweep, runExpiryWarning };
}

module.exports = {
  attachMarketModeration,
  contentChanged,
  nextStatusOnCreate,
  expiryDate,
  planShopItemWrite,
  normalizeReason,
  buildModerationPatch,
  planExpiry,
  needsExpiryWarning,
  renderMessage,
  samePhone,
  MESSAGES,
  CONTENT_FIELDS,
  EDIT_RESUBMIT_STATUSES,
  REJECT_STATUS,
  COLLECTIONS,
  EXPIRING,
  EXPIRY_DAYS,
  REALTY_DELETE_GUARD_MS,
  AUDIT_KIND,
};
