/**
 * Маҳсулот карточкаси белгиси (эга 2026-11-19): «−N%» · «Акция» · «Сўнгги доналар» · «Янги».
 *
 * Эга қарорлари (CONFIRMED, 2026-11-19):
 *   - карточкада БИТТА белги (устунлик: chegirma → aksiya → сўнгги доналар → янги); сотувчи эркин матн ёзмайди;
 *   - «−N%»: сотувчи эски нархни киритади, фоиз серверда (бутун сон, floor); эски нарх ≥ 7 кун ҳақиқатан
 *     нарх бўлган бўлиши шарт (сервер ёзадиган нарх тарихи); муддат ≤ 30 кун; «−N%» МОДЕРАЦИЯДАН ўтади;
 *   - «Янги» — фаоллашгандан 7 кун (автомат); «Сўнгги доналар» — қолдиқ < 5 (автомат).
 * PROPOSED (бу модулда, эга тасдиғи керак):
 *   - «Акция» (фоизсиз) — модерациясиз (эркин матн йўқ, фақат муддат ≤ 30 кун); суиистеъмол (ҳар 30 кунда қайта) —
 *     очиқ масала;
 *   - эски нарх даври тугаганига 30 кундан ошмаган бўлиши керак (`HISTORY_LOOKBACK_DAYS`) — бир йил олдинги
 *     нархни «эски нарх» деб кўрсатиб бўлмасин;
 *   - нарх ўзгарса тасдиқланган/кутилаётган «−N%» бекор (фоиз эскиради); сотувчи қайта юборади.
 *
 * Маълумот модели (коллекциялар: tv_shop_items `price`; wholesale_products — энг кичик minQty поғонасининг нархи):
 *   Мижоз ёзади:   promoRequest {kind: 'discount'|'promo', oldPrice?: int, until: Timestamp, requestedAt: request.time}
 *   ФАҚАТ сервер:  priceTracked, priceSince, priceHistory[{price, from, to}] (≤10),
 *                  promo {kind, percent?, oldPrice?, until, approvedAt, approvedBy} — карточкада кўринадиган белги,
 *                  promoState {status: pending|rejected|active|cleared, reason?, requestKey, ...},
 *                  firstActiveAt (биринчи фаоллашув), stockLeft (wholesale: қадоқлар қолдиғи йиғиндиси).
 *
 * Функциялар (ЯНГИ — мавжуд функциялар ўзгармади):
 *   - onShopItemPromoWrite / onWholesaleProductPromoWrite (onWrite): нарх тарихи, сўровни текшириш, firstActiveAt;
 *   - onWholesaleStockBadge (wholesale_stock onWrite): stockLeft;
 *   - adminModeratePromo (callable): «−N%» тасдиқлаш/рад этиш, транзакция + admin_audit (kind `promo_moderation`).
 * Идемпотентлик: ҳолат ҳужжатнинг ўзида (priceTracked, promoState.requestKey) — триггер қайта ишласа ҳам ёзув йўқ.
 */
'use strict';

const { normalizeLang, langOfPhone } = require('./notif_i18n');

const MODULE = 'product_promo';
const DAY_MS = 24 * 60 * 60 * 1000;
const PROMO_MAX_DAYS = 30;
const MIN_PRICE_DAYS = 7;
const HISTORY_LOOKBACK_DAYS = 30; // PROPOSED
const HISTORY_MAX = 10;
const PRICE_MAX = 999999999;
const LOW_STOCK_LIMIT = 5; // мижоз белгиси: 1..4 (маълумот учун; сервер фақат stockLeft ёзади)
const REASON_MAX = 300;
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const AUDIT_KIND = 'promo_moderation';
const COLLECTIONS = Object.freeze(['tv_shop_items', 'wholesale_products']);
const SERVER_KEYS = Object.freeze(['priceTracked', 'priceSince', 'priceHistory', 'promo', 'promoState', 'firstActiveAt', 'stockLeft']);

/** Рад этиш/бекор сабаблари (мижоз шу кодлар бўйича 3 тилда тушунтиради). */
const REASONS = Object.freeze({
  UNTIL_INVALID: 'UNTIL_INVALID',
  UNTIL_TOO_FAR: 'UNTIL_TOO_FAR',
  PRICE_REQUIRED: 'PRICE_REQUIRED',
  OLD_PRICE_INVALID: 'OLD_PRICE_INVALID',
  OLD_PRICE_NOT_HIGHER: 'OLD_PRICE_NOT_HIGHER',
  DISCOUNT_TOO_SMALL: 'DISCOUNT_TOO_SMALL',
  OLD_PRICE_NOT_7_DAYS: 'OLD_PRICE_NOT_7_DAYS',
  KIND_INVALID: 'KIND_INVALID',
  PRICE_CHANGED: 'PRICE_CHANGED',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED',
  ADMIN_REJECTED: 'ADMIN_REJECTED',
});

const MESSAGES = Object.freeze({
  promo_approved: {
    uz_Cyrl: { title: '✅ Чегирма тасдиқланди', body: '«{title}» карточкасида «−{percent}%» белгиси кўринади.' },
    uz_Latn: { title: '✅ Chegirma tasdiqlandi', body: '«{title}» kartochkasida «−{percent}%» belgisi ko\'rinadi.' },
    ru: { title: '✅ Скидка одобрена', body: 'На карточке «{title}» показан значок «−{percent}%».' },
  },
  promo_rejected: {
    uz_Cyrl: { title: '⛔ Чегирма қабул қилинмади', body: '«{title}»: {reason}' },
    uz_Latn: { title: '⛔ Chegirma qabul qilinmadi', body: '«{title}»: {reason}' },
    ru: { title: '⛔ Скидка отклонена', body: '«{title}»: {reason}' },
  },
});

function renderMessage(key, lang, params = {}) {
  const t = MESSAGES[key][normalizeLang(lang)];
  const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => (params[k] === undefined ? '' : String(params[k])));
  return { title: fill(t.title), body: fill(t.body) };
}

// ───────────────────────── Тоза ёрдамчилар (тестланади) ─────────────────────────

function millisOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === 'number') return v;
  return null;
}

const isPrice = (v) => Number.isSafeInteger(v) && v >= 0 && v <= PRICE_MAX;

/** Жорий нарх (int ёки null). wholesale — энг кичик minQty поғонаси (мижоз `basePrice` билан бир хил). */
function priceOf(collection, d) {
  const x = d || {};
  if (collection === 'wholesale_products') {
    const tiers = Array.isArray(x.priceTiers) ? x.priceTiers : [];
    let best = null;
    for (const t of tiers) {
      if (!t || !Number.isSafeInteger(t.minQty) || t.minQty < 1 || !isPrice(t.price) || t.price <= 0) continue;
      if (!best || t.minQty < best.minQty) best = t;
    }
    return best ? best.price : null;
  }
  return isPrice(x.price) ? x.price : null;
}

/** Чегирма фоизи: floor((old − price) × 100 / old), бутун сонлар. */
function discountPercent(oldPrice, price) {
  if (!Number.isSafeInteger(oldPrice) || !Number.isSafeInteger(price) || oldPrice <= 0 || price < 0 || price >= oldPrice) return 0;
  return Math.floor(((oldPrice - price) * 100) / oldPrice);
}

/** Сўров калити (идемпотентлик): бир хил сўров икки марта текширилмайди. */
function requestKeyOf(req) {
  if (!req || typeof req !== 'object') return null;
  return [String(req.kind || ''), Number.isSafeInteger(req.oldPrice) ? req.oldPrice : '', millisOf(req.until) || '', millisOf(req.requestedAt) || '']
    .join('|');
}

/** [oldPrice] нархи ≥ 7 кун бўлган ва якинда (≤ 30 кун олдин) тугаган давр борми. */
function oldPriceHeld(history, oldPrice, nowMs) {
  const list = Array.isArray(history) ? history : [];
  return list.some((h) => {
    if (!h || h.price !== oldPrice) return false;
    const from = millisOf(h.from);
    const to = millisOf(h.to);
    if (from == null || to == null) return false;
    return to - from >= MIN_PRICE_DAYS * DAY_MS && to >= nowMs - HISTORY_LOOKBACK_DAYS * DAY_MS;
  });
}

/**
 * Сўровни текшириш (тоза). `{ok: true, kind, percent?, oldPrice?, untilMs}` ёки `{ok: false, reason}`.
 * history — нарх ўзгариши қайд қилингандан КЕЙИНГИ тарих (бир ёзувда нарх тушириш + сўров ҳам ишлайди).
 */
function validatePromoRequest({ req, price, history, nowMs, priceUnit }) {
  const r = req || {};
  const untilMs = millisOf(r.until);
  const baseMs = millisOf(r.requestedAt) != null ? Math.min(millisOf(r.requestedAt), nowMs) : nowMs;
  if (r.kind !== 'discount' && r.kind !== 'promo') return { ok: false, reason: REASONS.KIND_INVALID };
  if (untilMs == null || untilMs <= nowMs) return { ok: false, reason: REASONS.UNTIL_INVALID };
  if (untilMs > baseMs + PROMO_MAX_DAYS * DAY_MS) return { ok: false, reason: REASONS.UNTIL_TOO_FAR };
  if (r.kind === 'promo') return { ok: true, kind: 'promo', untilMs };
  if (price == null || price <= 0 || priceUnit === 'negotiable') return { ok: false, reason: REASONS.PRICE_REQUIRED };
  if (!Number.isSafeInteger(r.oldPrice) || r.oldPrice <= 0 || r.oldPrice > PRICE_MAX) return { ok: false, reason: REASONS.OLD_PRICE_INVALID };
  if (r.oldPrice <= price) return { ok: false, reason: REASONS.OLD_PRICE_NOT_HIGHER };
  const percent = discountPercent(r.oldPrice, price);
  if (percent < 1) return { ok: false, reason: REASONS.DISCOUNT_TOO_SMALL };
  if (!oldPriceHeld(history, r.oldPrice, nowMs)) return { ok: false, reason: REASONS.OLD_PRICE_NOT_7_DAYS };
  return { ok: true, kind: 'discount', percent, oldPrice: r.oldPrice, untilMs };
}

/** Биринчи фаоллашув: янги ҳужжат active, ёки ҳеч қачон тасдиқланмаган ҳужжат active бўлди. */
function shouldStampFirstActive(collection, before, cur) {
  if (!cur || cur.status !== 'active' || cur.firstActiveAt) return false;
  if (!before) return true;
  if (before.status === 'active') return false;
  // Эски (аввал тасдиқланган) ҳужжат қайта фаоллашса — «янги» эмас.
  return collection === 'wholesale_products' ? !before.publishedAt && !before.moderatedAt : !before.moderatedAt;
}

/**
 * Режа (тоза): жорий ҳужжат бўйича патч. `fv` — { ts(), del(), at(ms) }. Ўзгариш бўлмаса — null.
 * `eventMs` — шу ёзув вақти (нарх даврлари чегараси), `before` — ҳодисадан олдинги ҳолат (firstActiveAt учун).
 */
function planPromoWrite(collection, before, cur, { nowMs, eventMs, fv }) {
  if (!cur) return null;
  const at = eventMs != null ? Math.min(eventMs, nowMs) : nowMs;
  const patch = {};
  const out = { patch, decision: null, priceChanged: false };
  const price = priceOf(collection, cur);
  let history = Array.isArray(cur.priceHistory) ? cur.priceHistory.slice() : [];

  // 1. Нарх тарихи.
  if (!('priceTracked' in cur) || cur.priceTracked === undefined) {
    patch.priceTracked = price;
    patch.priceSince = fv.at(at);
  } else if (cur.priceTracked !== price) {
    out.priceChanged = true;
    const from = millisOf(cur.priceSince);
    if (Number.isSafeInteger(cur.priceTracked) && from != null) {
      history.push({ price: cur.priceTracked, from: fv.at(from), to: fv.at(at), fromMs: from, toMs: at });
      history = history.slice(-HISTORY_MAX);
      patch.priceHistory = history.map((h) => ({ price: h.price, from: h.fromMs != null ? fv.at(h.fromMs) : h.from, to: h.toMs != null ? fv.at(h.toMs) : h.to }));
    }
    patch.priceTracked = price;
    patch.priceSince = fv.at(at);
  }
  const histForCheck = history.map((h) => ({ price: h.price, from: h.fromMs != null ? h.fromMs : h.from, to: h.toMs != null ? h.toMs : h.to }));

  const state = cur.promoState || {};
  const req = cur.promoRequest && typeof cur.promoRequest === 'object' ? cur.promoRequest : null;
  const key = requestKeyOf(req);
  const stateKey = state.requestKey || null;

  // 2. Нарх ўзгарди — «−N%» эскирди.
  if (out.priceChanged) {
    const activeDiscount = cur.promo && cur.promo.kind === 'discount';
    const pendingDiscount = state.status === 'pending';
    if (activeDiscount) patch.promo = fv.del();
    if (activeDiscount || pendingDiscount) {
      patch.promoState = { status: 'cleared', reason: REASONS.PRICE_CHANGED, requestKey: stateKey, at: fv.ts() };
      out.decision = 'cleared_price';
    }
  }

  // 3. Бекор қилиш (сўров ўчирилди).
  if (!req) {
    if (stateKey && (state.status === 'pending' || state.status === 'active')) {
      if (cur.promo) patch.promo = fv.del();
      patch.promoState = { status: 'cleared', reason: REASONS.CANCELLED, requestKey: null, at: fv.ts() };
      out.decision = 'cancelled';
    }
  } else if (key !== stateKey) {
    // 4. Янги сўров.
    const v = validatePromoRequest({ req, price, history: histForCheck, nowMs, priceUnit: cur.priceUnit });
    if (!v.ok) {
      patch.promoState = { status: 'rejected', reason: v.reason, requestKey: key, at: fv.ts() };
      out.decision = `rejected:${v.reason}`;
    } else if (v.kind === 'promo') {
      patch.promo = { kind: 'promo', until: fv.at(v.untilMs), approvedAt: fv.ts(), approvedBy: 'auto' };
      patch.promoState = { status: 'active', kind: 'promo', requestKey: key, until: fv.at(v.untilMs), at: fv.ts() };
      out.decision = 'promo_active';
    } else {
      patch.promoState = {
        status: 'pending', kind: 'discount', requestKey: key, percent: v.percent, oldPrice: v.oldPrice, price,
        until: fv.at(v.untilMs), at: fv.ts(),
      };
      out.decision = 'discount_pending';
    }
  }

  // 5. Биринчи фаоллашув.
  if (shouldStampFirstActive(collection, before, cur)) patch.firstActiveAt = fv.ts();

  return Object.keys(patch).length ? out : null;
}

/** Қадоқ ID'лари — functions_demand/api/wholesale_stock.js `packIdsOf` нусхаси (бошқа codebase; паритет тести бор). */
const PACK_ID_RE = /^(p[1-9]|default)$/;
function packIdsOf(product) {
  const raw = product && Array.isArray(product.packs) ? product.packs : [];
  const ids = [];
  for (const p of raw) {
    const id = p && typeof p.id === 'string' ? p.id.trim() : '';
    const label = p && typeof p.label === 'string' ? p.label.trim() : '';
    const tiers = p && Array.isArray(p.priceTiers) ? p.priceTiers : [];
    if (!PACK_ID_RE.test(id) || id === 'default' || !label || !tiers.length) continue;
    if (ids.includes(id)) continue;
    ids.push(id);
    if (ids.length >= 5) break;
  }
  return ids.length ? ids : ['default'];
}

/** Қолдиқ йиғиндиси: ҲАР қадоқ учун қолдиқ бўлса — йиғинди, акс ҳолда null (номаълум → белги йўқ). */
function stockLeftOf(product, stockDoc) {
  const packs = stockDoc && stockDoc.packs && typeof stockDoc.packs === 'object' ? stockDoc.packs : null;
  if (!packs) return null;
  let sum = 0;
  for (const id of packIdsOf(product)) {
    const q = packs[id];
    if (!Number.isSafeInteger(q) || q < 0) return null;
    sum += q;
  }
  return sum;
}

function normalizeReason(v) {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length >= 1 && s.length <= REASON_MAX ? s : null;
}

// ───────────────────────── Firebase қисми ─────────────────────────

function attachProductPromo(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles, notifyUserInApp } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const fv = { ts: () => FV.serverTimestamp(), del: () => FV.delete(), at: (ms) => admin.firestore.Timestamp.fromMillis(ms) };
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const log = (fields) => console.log(JSON.stringify({ module: MODULE, ...fields }));

  async function syncStockLeft(ref, product) {
    const st = await db.collection('wholesale_stock').doc(ref.id).get();
    const left = stockLeftOf(product, st.exists ? st.data() : null);
    const cur = Number.isSafeInteger(product.stockLeft) ? product.stockLeft : null;
    if (left === cur) return false;
    await ref.update({ stockLeft: left == null ? FV.delete() : left });
    return true;
  }

  function promoTrigger(collection, name) {
    return functions.firestore.document(`${collection}/{docId}`).onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const started = Date.now();
      const docId = context.params.docId;
      const before = change.before.exists ? (change.before.data() || {}) : null;
      const after = change.after.data() || {};
      const eventMs = millisOf(change.after.updateTime) || Date.parse(context.timestamp) || started;
      // Арзон олдиндан текшириш: ўзгариш йўқ бўлса — ўқиш/ёзув йўқ (viewCount каби ёзувлар).
      const pre = planPromoWrite(collection, before, after, { nowMs: started, eventMs, fv });
      let decision = null;
      if (pre) {
        decision = await db.runTransaction(async (t) => {
          const snap = await t.get(change.after.ref);
          if (!snap.exists) return 'gone';
          const plan = planPromoWrite(collection, before, snap.data() || {}, { nowMs: Date.now(), eventMs, fv });
          if (!plan) return 'noop';
          t.update(change.after.ref, plan.patch);
          return plan.decision || 'tracked';
        });
      }
      let stock = false;
      if (collection === 'wholesale_products'
          && (!before || JSON.stringify(packIdsOf(before)) !== JSON.stringify(packIdsOf(after)))) {
        stock = await syncStockLeft(change.after.ref, after);
      }
      if (decision || stock) {
        log({ action: name, collection, docId, result: decision || 'noop', stockSynced: stock, duration: Date.now() - started });
      }
      return null;
    });
  }

  exportsObj.onShopItemPromoWrite = promoTrigger('tv_shop_items', 'onShopItemPromoWrite');
  exportsObj.onWholesaleProductPromoWrite = promoTrigger('wholesale_products', 'onWholesaleProductPromoWrite');

  exportsObj.onWholesaleStockBadge = functions.firestore.document('wholesale_stock/{productId}').onWrite(async (change, context) => {
    const id = context.params.productId;
    const ref = db.collection('wholesale_products').doc(id);
    const p = await ref.get();
    if (!p.exists) return null;
    const changed = await syncStockLeft(ref, p.data() || {});
    if (changed) log({ action: 'onWholesaleStockBadge', productId: id, result: 'synced' });
    return null;
  });

  exportsObj.adminModeratePromo = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const d = data || {};
    const collection = String(d.collection || '');
    if (!COLLECTIONS.includes(collection)) throw fail('invalid-argument', 'COLLECTION_INVALID');
    const id = typeof d.id === 'string' ? d.id.trim() : '';
    if (!id || id.length > 128 || id.includes('/')) throw fail('invalid-argument', 'ID_INVALID');
    const decision = String(d.decision || '');
    if (decision !== 'approve' && decision !== 'reject') throw fail('invalid-argument', 'DECISION_INVALID');
    const note = decision === 'reject' ? normalizeReason(d.reason) : null;
    if (decision === 'reject' && !note) throw fail('invalid-argument', 'REASON_REQUIRED');
    const ref = db.collection(collection).doc(id);
    let res;
    try {
      res = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) throw fail('not-found', 'LISTING_NOT_FOUND');
        const cur = snap.data() || {};
        const st = cur.promoState || {};
        if (st.status !== 'pending') throw fail('failed-precondition', 'PROMO_NOT_PENDING', { status: String(st.status || '') });
        if (requestKeyOf(cur.promoRequest) !== st.requestKey) throw fail('failed-precondition', 'PROMO_STALE');
        const nowMs = Date.now();
        let outcome = decision;
        let reasonCode = null;
        if (decision === 'approve') {
          if (priceOf(collection, cur) !== st.price || cur.priceTracked !== st.price) { outcome = 'reject'; reasonCode = REASONS.PRICE_CHANGED; }
          else if ((millisOf(st.until) || 0) <= nowMs) { outcome = 'reject'; reasonCode = REASONS.EXPIRED; }
        } else {
          reasonCode = REASONS.ADMIN_REJECTED;
        }
        const audit = {
          kind: AUDIT_KIND, collection, id, target: id, decision: outcome, actor, at: fv.ts(),
          percent: st.percent || null, oldPrice: st.oldPrice || null, price: st.price || null, until: st.until || null,
          ...(reasonCode ? { reasonCode } : {}), ...(note ? { reason: note } : {}),
        };
        if (outcome === 'approve') {
          t.update(ref, {
            promo: { kind: 'discount', percent: st.percent, oldPrice: st.oldPrice, until: st.until, approvedAt: fv.ts(), approvedBy: actor },
            promoState: { ...st, status: 'active', decidedAt: fv.ts(), decidedBy: actor },
          });
        } else {
          t.update(ref, {
            promoState: { ...st, status: 'rejected', reason: reasonCode, ...(note ? { note } : {}), decidedAt: fv.ts(), decidedBy: actor },
          });
        }
        t.set(db.collection('admin_audit').doc(), audit);
        return { cur, st, outcome, reasonCode };
      });
    } catch (e) {
      const code = (e && e.details && e.details.code) || 'INTERNAL';
      log({ action: 'adminModeratePromo', collection, docId: id, userId: actor, decision, result: 'error', errorCode: code, duration: Date.now() - started });
      if (e instanceof HttpsError) throw e;
      throw fail('internal', 'PROMO_MODERATION_FAILED');
    }
    let notified = false;
    try {
      const phone = String(collection === 'tv_shop_items' ? res.cur.ownerPhone || '' : res.cur.sellerId || '').replace(/\D/g, '');
      const uid = phone.length === 9 ? `998${phone}` : phone;
      if (uid.length >= 12) {
        const lang = await langOfPhone(db, uid);
        const title = String(res.cur.title || '').trim().slice(0, 60);
        const msg = res.outcome === 'approve'
          ? renderMessage('promo_approved', lang, { title, percent: res.st.percent })
          : renderMessage('promo_rejected', lang, { title, reason: note || res.reasonCode });
        await notifyUserInApp({
          userId: uid, title: msg.title, body: msg.body, category: 'info', source: 'promo_moderation',
          dataType: res.outcome === 'approve' ? 'promo_approved' : 'promo_rejected', screen: 'news',
          extraData: { collection, listingId: id },
        });
        notified = true;
      }
    } catch (e) {
      log({ action: 'adminModeratePromo', collection, docId: id, result: 'error', errorCode: 'NOTIFY_FAILED', error: String(e.message || e) });
    }
    log({ action: 'adminModeratePromo', collection, docId: id, userId: actor, decision, result: res.outcome, reasonCode: res.reasonCode, notified, duration: Date.now() - started });
    return { ok: true, collection, id, status: res.outcome === 'approve' ? 'active' : 'rejected', reason: res.reasonCode };
  });
}

module.exports = {
  attachProductPromo,
  priceOf,
  discountPercent,
  requestKeyOf,
  oldPriceHeld,
  validatePromoRequest,
  shouldStampFirstActive,
  planPromoWrite,
  packIdsOf,
  stockLeftOf,
  renderMessage,
  REASONS,
  SERVER_KEYS,
  COLLECTIONS,
  PROMO_MAX_DAYS,
  MIN_PRICE_DAYS,
  HISTORY_LOOKBACK_DAYS,
  HISTORY_MAX,
  LOW_STOCK_LIMIT,
  AUDIT_KIND,
  DAY_MS,
};
