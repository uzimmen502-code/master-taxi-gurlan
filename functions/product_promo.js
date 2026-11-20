/**
 * Маҳсулот карточкаси белгиси: «−N%» · «Акция» · «Сўнгги доналар» · «Янги».
 *
 * Эга қарорлари (CONFIRMED):
 *   2026-11-19 — карточкада БИТТА белги (устунлик: −% → Акция → сўнгги доналар → янги); эркин матн йўқ;
 *     «Янги» — фаоллашгандан 7 кун; «Сўнгги доналар» — қолдиқ < 5; «Акция» — модерациясиз, ≤ 30 кун.
 *   2026-11-20 — «−N%» = ЖОРИЙ нархдан фоиз (эски нарх қўлда ёзилмайди). Мисол: 10 000, −10% → карточкада 10 000
 *     чизилган ва 9 000 қизил. Асос нарх охирги 30 кун ичида ≥ 7 кун товарнинг нархи бўлган бўлиши шарт; ≤ 30 кун.
 *     AVA дўкони (platform_products ва AVA'нинг ўз ulgurji товарлари) — админ панелдан бевосита (adminSetProductDiscount);
 *     бошқа сотувчилар — ўзлари сўрайди, «−%» модерациядан ўтади (adminModeratePromo).
 *     Харидор чегирмали нархни ТЎЛАЙДИ: тасдиқда сервер ҳақиқий нарх майдонларини чегирмали қийматга ёзади
 *     (tv_shop_items.price; wholesale priceTiers + packs[].priceTiers; platform price + priceTiers) ва асосни
 *     `promo.base` да сақлайди — мавжуд quote/order коди ўзгармасдан тўғри нархни олади.
 *     Акция пайтида сотувчи нархни ўзгартирса: янги нарх < асос → акция давом этади (фоиз асосдан қайта, floor);
 *     янги нарх == асос → бекор; янги нарх > асос → бекор (PROPOSED, эгага ҳисобот).
 *     Муддат тугаса (productPromoExpirySweep): нарх ҳали сервер қўйган чегирмали нарх бўлса — асос тикланади;
 *     сотувчи ўзгартирган бўлса — унинг нархи қолади, фақат белги олинади. Идемпотент.
 * Фоиз 1..50 — AVA_DECIDED (эга 2026-11-20). PROPOSED: эски нархлар даври фақат промо бўлмаган даврлардан; Акция суиистеъмоли — очиқ масала.
 *
 * Маълумот (мижоз ёзади фақат `promoRequest` {kind: discount|promo, percent?, until, requestedAt}):
 *   ФАҚАТ сервер: priceTracked, priceSince, priceHistory[{price, from, to, promo?}] (≤ 10),
 *     promo {kind, percent, basePrice, price, base{...}, applied{...}, sellerChanged?, until, approvedAt, approvedBy},
 *     promoState {status: pending|rejected|active|cleared|expired, reason?, requestKey, ...}, firstActiveAt, stockLeft.
 */
'use strict';

const { normalizeLang, langOfPhone } = require('./notif_i18n');

const MODULE = 'product_promo';
const DAY_MS = 24 * 60 * 60 * 1000;
const PROMO_MAX_DAYS = 30;
const MIN_PRICE_DAYS = 7;
const REFERENCE_WINDOW_DAYS = 30;
const HISTORY_MAX = 10;
const PRICE_MAX = 999999999;
const PERCENT_MIN = 1;
const PERCENT_MAX = 50; // AVA_DECIDED (эга 2026-11-20; аввал 90 PROPOSED эди)
const REASON_MAX = 300;
const PAGE = 300;
const MAX_ROUNDS = 20;
const ADMIN_ROLES = Object.freeze(['admin', 'superadmin']);
const AUDIT_KIND = 'promo_moderation';
const AUDIT_KIND_DIRECT = 'promo_admin_set';
/** Сотувчи сўрови мумкин бўлган коллекциялар; platform_products — фақат админ. */
const REQUEST_COLLECTIONS = Object.freeze(['tv_shop_items', 'wholesale_products']);
const COLLECTIONS = Object.freeze(['tv_shop_items', 'wholesale_products', 'platform_products']);
const SERVER_KEYS = Object.freeze(['priceTracked', 'priceSince', 'priceHistory', 'promo', 'promoState', 'firstActiveAt', 'stockLeft']);

const REASONS = Object.freeze({
  UNTIL_INVALID: 'UNTIL_INVALID',
  UNTIL_TOO_FAR: 'UNTIL_TOO_FAR',
  PRICE_REQUIRED: 'PRICE_REQUIRED',
  PERCENT_INVALID: 'PERCENT_INVALID',
  DISCOUNT_TOO_SMALL: 'DISCOUNT_TOO_SMALL',
  PRICE_NOT_7_DAYS: 'PRICE_NOT_7_DAYS',
  KIND_INVALID: 'KIND_INVALID',
  PRICE_CHANGED: 'PRICE_CHANGED',
  PRICE_RESTORED: 'PRICE_RESTORED',
  PRICE_ABOVE_BASE: 'PRICE_ABOVE_BASE',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED',
  ADMIN_REJECTED: 'ADMIN_REJECTED',
  ADMIN_CLEARED: 'ADMIN_CLEARED',
  REPLACED: 'REPLACED',
  PROMO_ACTIVE: 'PROMO_ACTIVE',
});

const MESSAGES = Object.freeze({
  promo_approved: {
    uz_Cyrl: { title: '✅ Чегирма тасдиқланди', body: '«{title}» карточкасида «−{percent}%» белгиси кўринади.' },
    uz_Latn: { title: '✅ Çegirma tasdiqlandi', body: '«{title}» kartoçkasida «−{percent}%» belgisi körinadi.' },
    ru: { title: '✅ Скидка одобрена', body: 'На карточке «{title}» показан значок «−{percent}%».' },
  },
  promo_rejected: {
    uz_Cyrl: { title: '⛔ Чегирма қабул қилинмади', body: '«{title}»: {reason}' },
    uz_Latn: { title: '⛔ Çegirma qabul qilinmadi', body: '«{title}»: {reason}' },
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

function stable(v) {
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (v && typeof v === 'object' && typeof v.toMillis !== 'function') {
    return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v === undefined ? null : v);
}

const isPrice = (v) => Number.isSafeInteger(v) && v >= 0 && v <= PRICE_MAX;

/** Асосий (солиштириладиган) нарх: tv/platform `price`; wholesale — энг кичик minQty поғонаси. */
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

/** Чегирмали нарх: floor(p × (100 − pct) / 100), камида 1. */
function discountedPrice(p, pct) {
  if (!Number.isSafeInteger(p) || p <= 0) return p;
  return Math.max(1, Math.floor((p * (100 - pct)) / 100));
}

/** Асосдан фоиз: floor((base − price) × 100 / base). */
function discountPercent(base, price) {
  if (!Number.isSafeInteger(base) || !Number.isSafeInteger(price) || base <= 0 || price < 0 || price >= base) return 0;
  return Math.floor(((base - price) * 100) / base);
}

const mapTiers = (tiers, f) => (Array.isArray(tiers)
  ? tiers.map((t) => (t && isPrice(t.price) ? { ...t, price: f(t.price) } : t)) : tiers);

/** Нарх майдонлари нусхаси (тиклаш учун). */
function priceFieldsOf(collection, d) {
  const x = d || {};
  if (collection === 'tv_shop_items') return { price: x.price === undefined ? null : x.price };
  if (collection === 'platform_products') {
    return { price: x.price === undefined ? null : x.price, priceTiers: Array.isArray(x.priceTiers) ? x.priceTiers : null };
  }
  return { priceTiers: Array.isArray(x.priceTiers) ? x.priceTiers : null, packs: Array.isArray(x.packs) ? x.packs : null };
}

/** Ҳар бир нархга фоиз (int floor) — tv/platform price, барча поғоналар, барча қадоқ поғоналари. */
function applyPercentToFields(collection, fields, pct) {
  const f = (p) => discountedPrice(p, pct);
  const out = {};
  if ('price' in fields) out.price = isPrice(fields.price) ? f(fields.price) : fields.price;
  if ('priceTiers' in fields) out.priceTiers = fields.priceTiers == null ? null : mapTiers(fields.priceTiers, f);
  if ('packs' in fields) {
    out.packs = fields.packs == null ? null
      : fields.packs.map((p) => (p && Array.isArray(p.priceTiers) ? { ...p, priceTiers: mapTiers(p.priceTiers, f) } : p));
  }
  return out;
}

/** Нусхани ҳужжат патчига: null — майдон ўчирилади. */
function fieldsToPatch(fields, fv) {
  const p = {};
  Object.keys(fields).forEach((k) => { p[k] = fields[k] == null ? fv.del() : fields[k]; });
  return p;
}

const sameFields = (collection, d, fields) => stable(priceFieldsOf(collection, d)) === stable(fields || {});

/** Қадоқларнинг нархдан бошқа майдонлари ўзгардими (wholesale: нарх-фақат таҳрир модерациясиз). */
function packsNonPriceChanged(a, b) {
  const strip = (packs) => (Array.isArray(packs)
    ? packs.map((p) => {
      if (!p || typeof p !== 'object') return p;
      // Поғоналар (нарх ва миқдор чегаралари) — нарх маълумоти, модерациясиз (эга 2026-11-20).
      const { priceTiers, ...rest } = p; // eslint-disable-line no-unused-vars
      return rest;
    }) : null);
  return stable(strip(a && a.packs)) !== stable(strip(b && b.packs));
}

/** Сўров калити (идемпотентлик). */
function requestKeyOf(req) {
  if (!req || typeof req !== 'object') return null;
  return [String(req.kind || ''), Number.isSafeInteger(req.percent) ? req.percent : '', millisOf(req.until) || '', millisOf(req.requestedAt) || '']
    .join('|');
}

const activeDiscount = (d) => !!(d && d.promo && d.promo.kind === 'discount' && Number.isSafeInteger(d.promo.basePrice));

/**
 * [price] охирги 30 кун ичида ≥ 7 кун товарнинг нархи бўлганми: ҳар бир (промо бўлмаган) даврнинг [now−30d, now]
 * билан кесишмаси ≥ 7 кун. Жорий давр (priceSince → now) — промо пайтида ҳисобланмайди.
 */
function referenceHeld(d, price, nowMs) {
  const x = d || {};
  const winStart = nowMs - REFERENCE_WINDOW_DAYS * DAY_MS;
  const periods = (Array.isArray(x.priceHistory) ? x.priceHistory : [])
    .filter((h) => h && h.promo !== true)
    .map((h) => ({ price: h.price, from: millisOf(h.from), to: millisOf(h.to) }));
  if (!activeDiscount(x) && x.priceTracked === price) periods.push({ price, from: millisOf(x.priceSince), to: nowMs });
  return periods.some((p) => p.price === price && p.from != null && p.to != null
    && Math.min(p.to, nowMs) - Math.max(p.from, winStart) >= MIN_PRICE_DAYS * DAY_MS);
}

function untilCheck(untilMs, baseMs, nowMs) {
  if (untilMs == null || untilMs <= nowMs) return REASONS.UNTIL_INVALID;
  if (untilMs > baseMs + PROMO_MAX_DAYS * DAY_MS) return REASONS.UNTIL_TOO_FAR;
  return null;
}

/** «−N%» шартлари (сўров, тасдиқ ва админ учун бир хил). `null` — яроқли, акс ҳолда сабаб. */
function discountProblem(collection, d, percent, nowMs) {
  const x = d || {};
  const price = priceOf(collection, x);
  if (!Number.isSafeInteger(percent) || percent < PERCENT_MIN || percent > PERCENT_MAX) return REASONS.PERCENT_INVALID;
  // Амалдаги чегирма устига иккинчиси йўқ (асос чегирмали нарх бўлиб қоларди): аввал бекор — асос тикланади.
  if (activeDiscount(x)) return REASONS.PROMO_ACTIVE;
  if (price == null || price <= 0 || x.priceUnit === 'negotiable') return REASONS.PRICE_REQUIRED;
  if (discountedPrice(price, percent) >= price) return REASONS.DISCOUNT_TOO_SMALL;
  if (!referenceHeld(x, price, nowMs)) return REASONS.PRICE_NOT_7_DAYS;
  return null;
}

/** Сотувчи сўровини текшириш (тоза). */
function validatePromoRequest(collection, d, req, nowMs) {
  const r = req || {};
  const reqAt = millisOf(r.requestedAt);
  const baseMs = reqAt != null ? Math.min(reqAt, nowMs) : nowMs;
  if (r.kind !== 'discount' && r.kind !== 'promo') return { ok: false, reason: REASONS.KIND_INVALID };
  const u = untilCheck(millisOf(r.until), baseMs, nowMs);
  if (u) return { ok: false, reason: u };
  if (r.kind === 'promo') return { ok: true, kind: 'promo', untilMs: millisOf(r.until) };
  const pr = discountProblem(collection, d, r.percent, nowMs);
  if (pr) return { ok: false, reason: pr };
  return { ok: true, kind: 'discount', percent: r.percent, untilMs: millisOf(r.until) };
}

/** Тарихга давр қўшиш (≤ 10). */
function pushHistory(d, entry, fv) {
  const list = (Array.isArray(d.priceHistory) ? d.priceHistory : []).slice();
  list.push({ price: entry.price, from: fv.at(entry.from), to: fv.at(entry.to), ...(entry.promo ? { promo: true } : {}) });
  return list.slice(-HISTORY_MAX);
}

/** Жорий давр ёпилиши (жорий нарх майдони кузатилаётган бўлса). */
function closeCurrentPeriod(d, atMs, fv) {
  const from = millisOf(d.priceSince);
  if (!Number.isSafeInteger(d.priceTracked) || from == null) return null;
  return pushHistory(d, { price: d.priceTracked, from, to: atMs, promo: activeDiscount(d) }, fv);
}

/**
 * Чегирмани қўллаш патчи: нарх майдонлари чегирмали, `promo` асос + қўлланган нусха, нарх кузатуви янги давр.
 */
function buildApplyPatch(collection, d, { percent, untilMs, actor, nowMs, fv, requestKey, extraState }) {
  const base = priceFieldsOf(collection, d);
  const applied = applyPercentToFields(collection, base, percent);
  const basePrice = priceOf(collection, d);
  const price = priceOf(collection, applied);
  const patch = {
    ...fieldsToPatch(applied, fv),
    promo: {
      kind: 'discount', percent, basePrice, price, base, applied, until: fv.at(untilMs), approvedAt: fv.ts(), approvedBy: actor,
    },
    promoState: { status: 'active', kind: 'discount', percent, requestKey: requestKey || null, at: fv.ts(), ...(extraState || {}) },
    priceTracked: price,
    priceSince: fv.at(nowMs),
  };
  const h = closeCurrentPeriod(d, nowMs, fv);
  if (h) patch.priceHistory = h;
  return patch;
}

/**
 * Акцияни якунлаш патчи (муддат, бекор, админ): чегирма бўлса ва нарх ҳали сервер қўйгани бўлса — асос тикланади;
 * сотувчи ўзгартирган бўлса — унинг нархи қолади. Белги доим олинади.
 */
function buildEndPatch(collection, d, { status, reason, nowMs, fv }) {
  const st = d.promoState || {};
  const patch = {
    promo: fv.del(),
    promoState: { status, reason, requestKey: st.requestKey || null, at: fv.ts() },
  };
  let restored = false;
  if (activeDiscount(d) && !d.promo.sellerChanged && d.promo.base && sameFields(collection, d, d.promo.applied)) {
    Object.assign(patch, fieldsToPatch(d.promo.base, fv));
    const h = closeCurrentPeriod(d, nowMs, fv);
    if (h) patch.priceHistory = h;
    patch.priceTracked = d.promo.basePrice;
    patch.priceSince = fv.at(nowMs);
    restored = true;
  }
  return { patch, restored };
}

/** Биринчи фаоллашув. platform_products — статус йўқ (`active` bool), «Янги» мижозда createdAt'дан. */
function shouldStampFirstActive(collection, before, cur) {
  if (collection === 'platform_products') return false;
  if (!cur || cur.status !== 'active' || cur.firstActiveAt) return false;
  if (!before) return true;
  if (before.status === 'active') return false;
  return collection === 'wholesale_products' ? !before.publishedAt && !before.moderatedAt : !before.moderatedAt;
}

/**
 * Триггер режаси (тоза). `{ patch, decision }` ёки null.
 */
function planPromoWrite(collection, before, cur, { nowMs, eventMs, fv }) {
  if (!cur) return null;
  const at = eventMs != null ? Math.min(eventMs, nowMs) : nowMs;
  const price = priceOf(collection, cur);
  const patch = {};
  let decision = null;
  let view = cur; // кейинги қадамлар учун ҳолат (нарх кузатуви янгиланган)

  // 1. Нарх кузатуви / сотувчи (ёки админ) нархни ўзгартирди.
  if (!('priceTracked' in cur) || cur.priceTracked === undefined) {
    patch.priceTracked = price;
    patch.priceSince = fv.at(at);
    view = { ...cur, priceTracked: price, priceSince: at };
  } else if (cur.priceTracked !== price) {
    const h = closeCurrentPeriod(cur, at, fv);
    if (h) patch.priceHistory = h;
    patch.priceTracked = price;
    patch.priceSince = fv.at(at);
    const st = cur.promoState || {};
    if (activeDiscount(cur)) {
      const base = cur.promo.basePrice;
      const pct = price == null ? 0 : discountPercent(base, price);
      if (price == null || price >= base || pct < 1) {
        patch.promo = fv.del();
        const reason = price === base ? REASONS.PRICE_RESTORED : (price != null && price > base ? REASONS.PRICE_ABOVE_BASE : REASONS.DISCOUNT_TOO_SMALL);
        patch.promoState = { status: 'cleared', reason, requestKey: st.requestKey || null, at: fv.ts() };
        decision = `cancelled:${reason}`;
        view = { ...cur, promo: null, promoState: patch.promoState };
      } else {
        // Белги PERCENT_MAX'дан ошмайди (эга 2026-11-20, а-вариант): сотувчи нархи ўзгармайди, акция давом этади.
        const shown = Math.min(pct, PERCENT_MAX);
        patch.promo = { ...cur.promo, percent: shown, sellerChanged: true };
        patch.promoState = { ...st, percent: shown };
        decision = 'continued';
        view = { ...cur, promo: patch.promo, promoState: patch.promoState };
      }
    } else if (st.status === 'pending') {
      patch.promoState = { status: 'cleared', reason: REASONS.PRICE_CHANGED, requestKey: st.requestKey || null, at: fv.ts() };
      decision = 'pending_cleared';
      view = { ...cur, promoState: patch.promoState };
    }
    view = { ...view, priceTracked: price, priceSince: at, priceHistory: h || cur.priceHistory };
  }

  // 2. Сотувчи сўрови (platform — йўқ).
  if (REQUEST_COLLECTIONS.includes(collection)) {
    const st = view.promoState || {};
    const req = view.promoRequest && typeof view.promoRequest === 'object' ? view.promoRequest : null;
    const key = requestKeyOf(req);
    const stateKey = st.requestKey || null;
    if (!req) {
      if (stateKey && (st.status === 'pending' || st.status === 'active')) {
        const end = view.promo ? buildEndPatch(collection, view, { status: 'cleared', reason: REASONS.CANCELLED, nowMs, fv }) : null;
        if (end) Object.assign(patch, end.patch);
        else patch.promoState = { status: 'cleared', reason: REASONS.CANCELLED, requestKey: null, at: fv.ts() };
        patch.promoState.requestKey = null;
        decision = end && end.restored ? 'cancelled_restored' : 'cancelled';
      }
    } else if (key !== stateKey) {
      const v = validatePromoRequest(collection, view, req, nowMs);
      if (!v.ok) {
        patch.promoState = { status: 'rejected', reason: v.reason, requestKey: key, at: fv.ts() };
        decision = `rejected:${v.reason}`;
      } else if (v.kind === 'promo') {
        if (activeDiscount(view)) Object.assign(patch, buildEndPatch(collection, view, { status: 'cleared', reason: REASONS.REPLACED, nowMs, fv }).patch);
        patch.promo = { kind: 'promo', until: fv.at(v.untilMs), approvedAt: fv.ts(), approvedBy: 'auto' };
        patch.promoState = { status: 'active', kind: 'promo', requestKey: key, until: fv.at(v.untilMs), at: fv.ts() };
        decision = 'promo_active';
      } else {
        // Амалдаги белги (чегирма/акция) — модерация қароригача қолади.
        patch.promoState = {
          status: 'pending', kind: 'discount', requestKey: key, percent: v.percent, price,
          newPrice: discountedPrice(price, v.percent), until: fv.at(v.untilMs), at: fv.ts(),
        };
        decision = 'discount_pending';
      }
    }
  }

  // 3. Ulgurji: нарх-фақат таҳрир active қолади (rules); қадоқларнинг бошқа майдони ўзгарса — сервер модерацияга.
  if (collection === 'wholesale_products' && before && before.status === 'active' && cur.status === 'active'
      && packsNonPriceChanged(before, cur)) {
    patch.status = 'pending';
    decision = decision ? `${decision}+packs_pending` : 'packs_pending';
  }

  // 4. Биринчи фаоллашув.
  if (shouldStampFirstActive(collection, before, cur)) patch.firstActiveAt = fv.ts();

  return Object.keys(patch).length ? { patch, decision } : null;
}

/** Қадоқ ID'лари — functions_demand/api/wholesale_stock.js `packIdsOf` нусхаси (бошқа codebase). */
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
  exportsObj.onPlatformProductPromoWrite = promoTrigger('platform_products', 'onPlatformProductPromoWrite');

  exportsObj.onWholesaleStockBadge = functions.firestore.document('wholesale_stock/{productId}').onWrite(async (change, context) => {
    const id = context.params.productId;
    const ref = db.collection('wholesale_products').doc(id);
    const p = await ref.get();
    if (!p.exists) return null;
    const changed = await syncStockLeft(ref, p.data() || {});
    if (changed) log({ action: 'onWholesaleStockBadge', productId: id, result: 'synced' });
    return null;
  });

  function parseTarget(d, allowed) {
    const collection = String((d && d.collection) || '');
    if (!allowed.includes(collection)) throw fail('invalid-argument', 'COLLECTION_INVALID');
    const id = d && typeof d.id === 'string' ? d.id.trim() : '';
    if (!id || id.length > 128 || id.includes('/')) throw fail('invalid-argument', 'ID_INVALID');
    return { collection, id, ref: db.collection(collection).doc(id) };
  }

  async function notifySeller(collection, cur, id, key, params) {
    try {
      const raw = collection === 'tv_shop_items' ? cur.ownerPhone : cur.sellerId;
      const digits = String(raw || '').replace(/\D/g, '');
      const uid = digits.length === 9 ? `998${digits}` : digits;
      if (uid.length < 12) return false;
      const lang = await langOfPhone(db, uid);
      const msg = renderMessage(key, lang, params);
      await notifyUserInApp({
        userId: uid, title: msg.title, body: msg.body, category: 'info', source: 'promo_moderation',
        dataType: key, screen: 'news', extraData: { collection, listingId: id },
      });
      return true;
    } catch (e) {
      log({ action: 'notifySeller', collection, docId: id, result: 'error', errorCode: 'NOTIFY_FAILED', error: String(e.message || e) });
      return false;
    }
  }

  // ── Сотувчи «−N%» сўрови модерацияси ──
  exportsObj.adminModeratePromo = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const { collection, id, ref } = parseTarget(data, REQUEST_COLLECTIONS);
    const decision = String((data && data.decision) || '');
    if (decision !== 'approve' && decision !== 'reject') throw fail('invalid-argument', 'DECISION_INVALID');
    const note = decision === 'reject' ? normalizeReason(data && data.reason) : null;
    if (decision === 'reject' && !note) throw fail('invalid-argument', 'REASON_REQUIRED');
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
        let reasonCode = decision === 'reject' ? REASONS.ADMIN_REJECTED : null;
        if (decision === 'approve') {
          if (priceOf(collection, cur) !== st.price || cur.priceTracked !== st.price) reasonCode = REASONS.PRICE_CHANGED;
          else if ((millisOf(st.until) || 0) <= nowMs) reasonCode = REASONS.EXPIRED;
          else reasonCode = discountProblem(collection, cur, st.percent, nowMs);
          if (reasonCode) outcome = 'reject';
        }
        const audit = {
          kind: AUDIT_KIND, collection, id, target: id, decision: outcome, actor, at: fv.ts(),
          percent: st.percent || null, price: st.price || null, newPrice: st.newPrice || null, until: st.until || null,
          ...(reasonCode ? { reasonCode } : {}), ...(note ? { reason: note } : {}),
        };
        if (outcome === 'approve') {
          // Аввалги белги (акция) бўлса — ўрнига (асос жорий нарх, чунки чегирма йўқ).
          const patch = buildApplyPatch(collection, cur, {
            percent: st.percent, untilMs: millisOf(st.until), actor, nowMs, fv, requestKey: st.requestKey,
            extraState: { decidedAt: fv.ts(), decidedBy: actor },
          });
          t.update(ref, patch);
          audit.newPrice = patch.promo.price;
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
    const title = String(res.cur.title || '').trim().slice(0, 60);
    const notified = res.outcome === 'approve'
      ? await notifySeller(collection, res.cur, id, 'promo_approved', { title, percent: res.st.percent })
      : await notifySeller(collection, res.cur, id, 'promo_rejected', { title, reason: note || res.reasonCode });
    log({ action: 'adminModeratePromo', collection, docId: id, userId: actor, decision, result: res.outcome, reasonCode: res.reasonCode, notified, duration: Date.now() - started });
    return { ok: true, collection, id, status: res.outcome === 'approve' ? 'active' : 'rejected', reason: res.reasonCode };
  });

  // ── AVA дўкони: админ «−N%» ни бевосита қўяди / олади ──
  exportsObj.adminSetProductDiscount = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, ADMIN_ROLES, 'Admin role required');
    const { collection, id, ref } = parseTarget(data, COLLECTIONS);
    const action = String((data && data.action) || '');
    if (action !== 'set' && action !== 'clear') throw fail('invalid-argument', 'ACTION_INVALID');
    const percent = data && data.percent;
    const untilMs = data && Number.isSafeInteger(data.untilMs) ? data.untilMs : null;
    let res;
    try {
      res = await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) throw fail('not-found', 'LISTING_NOT_FOUND');
        const cur = snap.data() || {};
        const nowMs = Date.now();
        let patch;
        const audit = { kind: AUDIT_KIND_DIRECT, collection, id, target: id, action, actor, at: fv.ts() };
        if (action === 'clear') {
          if (!cur.promo) throw fail('failed-precondition', 'PROMO_NONE');
          const end = buildEndPatch(collection, cur, { status: 'cleared', reason: REASONS.ADMIN_CLEARED, nowMs, fv });
          patch = end.patch;
          Object.assign(audit, { restored: end.restored, percent: (cur.promo && cur.promo.percent) || null });
        } else {
          const u = untilCheck(untilMs, nowMs, nowMs);
          if (u) throw fail('invalid-argument', u);
          const pr = discountProblem(collection, cur, percent, nowMs);
          if (pr) throw fail('failed-precondition', pr);
          patch = buildApplyPatch(collection, cur, { percent, untilMs, actor, nowMs, fv, requestKey: requestKeyOf(cur.promoRequest) });
          Object.assign(audit, { percent, price: priceOf(collection, cur), newPrice: patch.promo.price, until: fv.at(untilMs) });
        }
        t.update(ref, patch);
        t.set(db.collection('admin_audit').doc(), audit);
        return { newPrice: patch.promo && patch.promo.price ? patch.promo.price : null };
      });
    } catch (e) {
      const code = (e && e.details && e.details.code) || 'INTERNAL';
      log({ action: 'adminSetProductDiscount', collection, docId: id, userId: actor, op: action, result: 'error', errorCode: code, duration: Date.now() - started });
      if (e instanceof HttpsError) throw e;
      throw fail('internal', 'PROMO_SET_FAILED');
    }
    log({ action: 'adminSetProductDiscount', collection, docId: id, userId: actor, op: action, result: 'ok', duration: Date.now() - started });
    return { ok: true, collection, id, action, newPrice: res.newPrice };
  });

  // ── Муддат супуриш ──
  async function runPromoExpirySweep(nowMs = Date.now()) {
    const stats = {};
    const cutoff = admin.firestore.Timestamp.fromMillis(nowMs);
    for (const collection of COLLECTIONS) {
      const s = { ended: 0, restored: 0 };
      for (let round = 0; round < MAX_ROUNDS; round += 1) {
        const snap = await db.collection(collection).where('promo.until', '<=', cutoff).orderBy('promo.until').limit(PAGE).get();
        if (snap.empty) break;
        for (const doc of snap.docs) {
          try {
            const r = await db.runTransaction(async (t) => {
              const cur = await t.get(doc.ref);
              const d = cur.exists ? (cur.data() || {}) : null;
              if (!d || !d.promo || (millisOf(d.promo.until) || 0) > nowMs) return null;
              const end = buildEndPatch(collection, d, { status: 'expired', reason: REASONS.EXPIRED, nowMs: Date.now(), fv });
              t.update(doc.ref, end.patch);
              return end.restored;
            });
            if (r !== null) { s.ended += 1; if (r) s.restored += 1; }
          } catch (e) {
            log({ action: 'productPromoExpirySweep', collection, docId: doc.id, result: 'error', errorCode: 'SWEEP_DOC_FAILED', error: String(e.message || e) });
          }
        }
        if (snap.size < PAGE) break;
      }
      stats[collection] = s;
    }
    return stats;
  }

  exportsObj.productPromoExpirySweep = functions
    .runWith({ timeoutSeconds: 540 })
    .pubsub.schedule('every 15 minutes')
    .onRun(async () => {
      const started = Date.now();
      const stats = await runPromoExpirySweep(started);
      log({ action: 'productPromoExpirySweep', result: 'ok', stats, duration: Date.now() - started });
      return null;
    });

  return { runPromoExpirySweep };
}

module.exports = {
  attachProductPromo,
  priceOf,
  discountedPrice,
  discountPercent,
  priceFieldsOf,
  applyPercentToFields,
  sameFields,
  packsNonPriceChanged,
  requestKeyOf,
  referenceHeld,
  discountProblem,
  validatePromoRequest,
  buildApplyPatch,
  buildEndPatch,
  shouldStampFirstActive,
  planPromoWrite,
  packIdsOf,
  stockLeftOf,
  renderMessage,
  REASONS,
  SERVER_KEYS,
  COLLECTIONS,
  REQUEST_COLLECTIONS,
  PROMO_MAX_DAYS,
  MIN_PRICE_DAYS,
  REFERENCE_WINDOW_DAYS,
  PERCENT_MIN,
  PERCENT_MAX,
  HISTORY_MAX,
  AUDIT_KIND,
  AUDIT_KIND_DIRECT,
  DAY_MS,
};
