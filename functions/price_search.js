/**
 * «AVA AI — Ақлли нарх қидируви», 1-босқич (эга 2026-11-17, CONFIRMED).
 *
 * НИМА: фойдаланувчи ёзган матн бўйича AVA бозорларидаги таклифлар рўйхати — ҳар бирида маҳсулот нархи +
 *   харидор жойигача етказиш нархи = жами; ЖАМИ бўйича тартибланади.
 * МАНБАЛАР (фақат AVA, ташқи платформа ЙЎҚ):
 *   - `tv_shop_items` — бозор эълонлари ва Аралаш ўз дўкони маҳсулотлари («чакана»);
 *   - `wholesale_products` — Улгуржи (Хитой `market == 'china'` КИРМАЙДИ; «улгуржи», MOQ/қадоқ маълумоти билан).
 * ҚИДИРУВ: мавжуд сервер `searchTokens` (tv_shop_items — `market_search_tokens.js`; wholesale — илова ёзган
 *   `AdSearchText.buildTokens`). Сўров сўзлари АЙНАН ўша нормализация (`market_search_tokens.words/toLatin/
 *   toCyrillic`) билан, `array-contains-any`. Қатъий мослаштириш йўқ — бир нечта мос таклиф. LLM ЙЎҚ (1-босқич:
 *   оддий токен қидируви); нарх/етказиш ҳисоби — фақат шу детерминистик код.
 * ЕТКАЗИШ (нарх ўйлаб топилмайди — тариф йўқ/тўлиқ эмас бўлса `delivery.fee = null` + `reason`):
 *   - ШУ ТУМАН (чакана ҳам, улгуржи ҳам — эга 2026-11-17, CONFIRMED): бизнес буюртмаларининг МАВЖУД маҳаллий тарифи (`settings/restaurant_delivery`,
 *     `restaurant_delivery_tariff.js` соф функциялари — quoteBusinessOrder билан БИТТА манба). Масофа — тўғри чизиқ ×
 *     тарифдаги `roadFactor` (quoteBusinessOrder'нинг маршрутсиз «estimate» йўли; ҳар таклиф учун Directions API
 *     чақирилмайди — нарх 37). Вазнга боғлиқ эмас.
 *   - БОШҚА ТУМАН/ВИЛОЯТ (чакана ва улгуржи): AVA Logistics зона тарифи — ФАОЛ версия (`module_tariffs/logistics`
 *     кўрсаткичи → `logistics_v{N}`, status active; админ «AVA Logistics → Тариф» да фаоллаштирган). Ҳисоб —
 *     `logistics_tariff.js` (= functions_demand/core/tariff.js нусхаси, паритет тести) `quoteParcel`, Улгуржи
 *     буюртмасидаги каби `dimsOptional` + `declaredValue = товар суммаси`.
 *     ФАРҚ (эгага маълум қилинди): ҳақиқий Улгуржи буюртмаси (`quoteWholesaleOrder`, ЎЗГАРТИРИЛМАДИ) шу туманда ҳам
 *     зона тарифини олади — қидирувдаги маҳаллий нарх буюртмадагидан фарқ қилиши мумкин.
 *   - Вазн: маҳсулотда `unitWeightG` (tv_shop_items — ихтиёрий «тахминий вазн», Улгуржида — мавжуд майдон) бўлса аниқ
 *     поғона; бўлмаса энг кичик поғона (1 г) → «≈ X сўмдан» (`fromPrice: true`).
 *   - Якуний нарх ҲАР ДОИМ буюртма пайтида серверда (мавжуд буюртма занжирлари ўзгармайди).
 * РЕКЛАМА: `boostUntil` тартибга ТАЪСИР ҚИЛМАЙДИ — фақат `sponsored: true` белгиси (PROPOSED).
 * ЖАМИ: чакана — 1 бирлик; улгуржи — минимал буюртма (MOQ) миқдори (CONFIRMED, эга 2026-11-17).
 */
'use strict';

const crypto = require('crypto');
const searchText = require('./market_search_tokens');
const localTariff = require('./restaurant_delivery_tariff');
const zoneTariff = require('./logistics_tariff');
const platformPricing = require('./platform_pricing');
const { isLargeDeliveryLine } = require('./business_orders');

const RETAIL = 'retail';
const WHOLESALE = 'wholesale';
const SRC_RETAIL = 'tv_shop_items';
const SRC_WHOLESALE = 'wholesale_products';
const MARKET_CHINA = 'china';

const MAX_QUERY_CHARS = 100;
const MAX_QUERY_WORDS = 4;
/** Firestore `array-contains-any` чегараси 30. */
const MAX_QUERY_TOKENS = 30;
const FETCH_LIMIT_DEFAULT = 60;
const FETCH_LIMIT_MAX = 100;
const RESULT_LIMIT_DEFAULT = 30;
const MAX_UNIT_WEIGHT_G = 10000000; // firestore.rules wholesale/tv_shop_items unitWeightG чегараси билан бир хил
const MAX_PRICE = 999999999;
const GEO_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const PHONE_RE = /^998\d{9}$/;
/** Нарх кўрсатилмайдиган бирликлар: келишилади. */
const NON_PRICED_UNITS = Object.freeze(['negotiable']);
const FROM_UNITS = Object.freeze(['from']);

const REASONS = Object.freeze({
  TARIFF_NOT_ACTIVE: 'tariff_not_active',
  LOCAL_TARIFF_MISSING: 'local_tariff_missing',
  ZONE_NOT_FOUND: 'zone_not_found',
  BUYER_LOCATION_MISSING: 'buyer_location_missing',
  SELLER_LOCATION_MISSING: 'seller_location_missing',
  DELIVERY_TOO_FAR: 'delivery_too_far',
  DELIVERY_QUOTE_REQUIRED: 'delivery_quote_required',
  TARIFF_ERROR: 'tariff_error',
});

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isPosInt = (n) => isInt(n) && n > 0;
const str = (v, max = 200) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

function validLatLng(lat, lng) {
  return typeof lat === 'number' && typeof lng === 'number' && Number.isFinite(lat) && Number.isFinite(lng)
    && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
}

function msOf(v) {
  if (!v) return 0;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

// ─────────────────────────────────────────────────────────────────────────
// СЎРОВ
// ─────────────────────────────────────────────────────────────────────────

/**
 * Матн → сўзлар (≤4) ва `array-contains-any` токенлари (асл + лотин + кирилл, ≤30).
 * Нормализация — `market_search_tokens.js` (= илова `AdSearchText`).
 * @returns {{words: string[][], tokens: string[]}} words[i] — i-сўзнинг вариантлари
 */
function parseQuery(text) {
  const raw = String(text == null ? '' : text).slice(0, MAX_QUERY_CHARS);
  const seen = new Set();
  const words = [];
  for (const w of searchText.words(raw)) {
    if (seen.has(w)) continue;
    seen.add(w);
    const variants = [...new Set([w, searchText.toLatin(w), searchText.toCyrillic(w)]
      .filter((v) => v.length >= 2))];
    words.push(variants);
    if (words.length >= MAX_QUERY_WORDS) break;
  }
  const tokens = [];
  for (const vs of words) for (const v of vs) if (!tokens.includes(v) && tokens.length < MAX_QUERY_TOKENS) tokens.push(v);
  return { words, tokens };
}

/** Ҳужжат сўзга мос: токенлардан бири вариант ёки сарлавҳада қисм сифатида бор. */
function wordMatches(variants, docTokens, titleLower) {
  for (const v of variants) {
    if (docTokens.has(v)) return true;
    if (titleLower && titleLower.includes(v)) return true;
  }
  return false;
}

/** Нечта сўз мос келди (0..words.length). */
function matchCount(words, doc) {
  const tokens = new Set(Array.isArray(doc.searchTokens) ? doc.searchTokens.map(String) : []);
  const title = searchText.foldMarks(doc.title || '');
  let n = 0;
  for (const vs of words) if (wordMatches(vs, tokens, title)) n += 1;
  return n;
}

// ─────────────────────────────────────────────────────────────────────────
// ТАКЛИФЛАР (соф)
// ─────────────────────────────────────────────────────────────────────────

function validWeight(v) {
  return isPosInt(v) && v <= MAX_UNIT_WEIGHT_G ? v : null;
}

/**
 * Чакана таклиф (`tv_shop_items`). Нархсиз/хизмат/келишилади/нофаол → null.
 * Фақат ҳақиқий бутун нарх (18-қоида — ҳужжатни эгаси ёзади).
 */
function retailOfferFrom(id, d, nowMs) {
  if (!d || typeof d !== 'object') return null;
  const hasMarket = typeof d.market === 'string' && d.market !== '';
  const status = hasMarket ? String(d.status == null ? '' : d.status) : String(d.status || 'active');
  if (status !== 'active') return null;
  if (d.blockedByParent === true) return null;
  if (String(d.kind || 'product') !== 'product') return null;
  const priceUnit = typeof d.priceUnit === 'string' ? d.priceUnit : '';
  if (NON_PRICED_UNITS.includes(priceUnit)) return null;
  const price = d.price;
  if (!isPosInt(price) || price > MAX_PRICE) return null;
  const exp = msOf(d.expiresAt);
  if (exp && exp <= nowMs) return null;
  const photos = Array.isArray(d.photoUrls) ? d.photoUrls.filter((u) => typeof u === 'string') : [];
  return {
    id,
    source: SRC_RETAIL,
    kind: RETAIL,
    title: str(d.title, 120),
    photoUrl: str(d.photoUrl, 500) || photos[0] || '',
    sellerName: str(d.ownerName, 80),
    ownerPhone: str(d.ownerPhone, 20),
    businessId: str(d.businessId, 128),
    market: hasMarket ? d.market : '',
    category: typeof d.category === 'string' ? d.category : '',
    districtId: str(d.districtId, 64),
    regionId: str(d.regionId, 64),
    price,
    priceUnit,
    priceFrom: FROM_UNITS.includes(priceUnit),
    qty: 1,
    goodsTotal: price,
    unitWeightG: validWeight(d.unitWeightG),
    dims: null,
    listedAt: msOf(d.createdAt) || null,
    sponsored: msOf(d.boostUntil) > nowMs,
  };
}

/** Қадоқлар (ёки қадоқсиз маҳсулот) ичидан энг арзон минимал буюртма. */
function cheapestWholesaleOption(d) {
  const opts = [];
  const productMoq = isPosInt(d.minOrderQty) ? d.minOrderQty : 1;
  const packs = Array.isArray(d.packs) ? d.packs.filter((p) => p && typeof p === 'object') : [];
  const sources = packs.length
    ? packs.map((p) => ({ label: str(p.label, 40), tiers: p.priceTiers, w: p.unitWeightG, dims: p.unitDims, moqField: isPosInt(p.minOrderQty) ? p.minOrderQty : 1 }))
    : [{ label: '', tiers: d.priceTiers, w: d.unitWeightG, dims: d.unitDims, moqField: productMoq }];
  for (const s of sources) {
    const tiers = platformPricing.cleanTiers(s.tiers);
    if (!tiers.length) continue;
    const moq = Math.max(s.moqField, tiers[0].minQty);
    let unitPrice = tiers[0].price;
    for (const t of tiers) { if (moq >= t.minQty) unitPrice = t.price; else break; }
    const goodsTotal = unitPrice * moq;
    if (!Number.isSafeInteger(goodsTotal)) continue;
    opts.push({ label: s.label, unitPrice, moq, goodsTotal, unitWeightG: validWeight(s.w), dims: validDims(s.dims) });
  }
  opts.sort((a, b) => a.goodsTotal - b.goodsTotal || a.unitPrice - b.unitPrice);
  return { best: opts[0] || null, packsCount: packs.length };
}

function validDims(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const d = { l: raw.l, w: raw.w, h: raw.h };
  return [d.l, d.w, d.h].every((x) => isInt(x) && x >= 1 && x <= 1000) ? d : null;
}

/** Улгуржи таклиф (`wholesale_products`, Хитойсиз). */
function wholesaleOfferFrom(id, d) {
  if (!d || typeof d !== 'object') return null;
  if (String(d.status || '') !== 'active') return null;
  if (String(d.market || '') === MARKET_CHINA) return null;
  const { best, packsCount } = cheapestWholesaleOption(d);
  if (!best || best.unitPrice > MAX_PRICE) return null;
  const images = Array.isArray(d.imageUrls) ? d.imageUrls.filter((u) => typeof u === 'string') : [];
  return {
    id,
    source: SRC_WHOLESALE,
    kind: WHOLESALE,
    title: str(d.title, 120),
    photoUrl: images[0] || '',
    sellerName: str(d.sellerCompanyName, 80),
    ownerPhone: str(d.sellerId, 20),
    businessId: '',
    market: '',
    category: '',
    districtId: str(d.districtId, 64),
    regionId: '',
    price: best.unitPrice,
    priceUnit: '',
    unit: str(d.unit, 20) || 'дона',
    priceFrom: false,
    qty: best.moq,
    moq: best.moq,
    packLabel: best.label,
    packsCount,
    goodsTotal: best.goodsTotal,
    unitWeightG: best.unitWeightG,
    dims: best.moq === 1 ? best.dims : null,
    listedAt: msOf(d.publishedAt) || msOf(d.createdAt) || null,
    sponsored: false,
  };
}

// ─────────────────────────────────────────────────────────────────────────
// ЕТКАЗИШ (соф)
// ─────────────────────────────────────────────────────────────────────────

/**
 * Маҳаллий (шу туман) — бизнес буюртмаси тарифи, маршрутсиз баҳолаш.
 * @returns {{fee:number|null, reason:string|null, method:'local', tariffVersion:number|null, distanceMeters?:number}}
 */
function localDelivery({ tariffDoc, from, to, now }) {
  const base = { method: 'local', fromPrice: false, tariffVersion: null };
  if (!from || !validLatLng(from.lat, from.lng)) return { ...base, fee: null, reason: REASONS.SELLER_LOCATION_MISSING };
  if (!to || !validLatLng(to.lat, to.lng)) return { ...base, fee: null, reason: REASONS.BUYER_LOCATION_MISSING };
  const prices = localTariff.resolveDeliveryPrices(tariffDoc, localTariff.resolveRegionKey(from.lat, from.lng));
  if (!prices) return { ...base, fee: null, reason: REASONS.LOCAL_TARIFF_MISSING };
  const straight = localTariff.haversineMeters(from.lat, from.lng, to.lat, to.lng);
  const distanceMeters = Math.round((straight * prices.roadFactorPermille) / 1000);
  if (distanceMeters > prices.maxKm * 1000) {
    return { ...base, fee: null, reason: REASONS.DELIVERY_TOO_FAR, tariffVersion: prices.version };
  }
  const night = localTariff.isNightAt(now, prices.nightStartH, prices.nightEndH);
  const r = localTariff.computeDeliveryFee({ distanceMeters, prices, night });
  return { ...base, fee: r.fee, reason: null, tariffVersion: prices.version, distanceMeters };
}

/**
 * Зона тарифи (фаол версия). Вазн йўқ → энг кичик поғона, `fromPrice: true`.
 * @returns {{fee:number|null, reason:string|null, method:'zone', fromPrice:boolean, tariffVersion:number|null}}
 */
function zoneDelivery({ tariff, origin, dest, offer }) {
  const base = { method: 'zone', fromPrice: false, tariffVersion: tariff ? tariff.version || null : null };
  if (!tariff) return { ...base, fee: null, reason: REASONS.TARIFF_NOT_ACTIVE };
  if (!origin || !origin.regionId) return { ...base, fee: null, reason: REASONS.SELLER_LOCATION_MISSING };
  if (!dest || !dest.regionId) return { ...base, fee: null, reason: REASONS.BUYER_LOCATION_MISSING };
  const known = isPosInt(offer.unitWeightG) && Number.isSafeInteger(offer.unitWeightG * offer.qty);
  const parcel = {
    actualWeightG: known ? offer.unitWeightG * offer.qty : 1,
    ...(known && offer.dims ? { lengthCm: offer.dims.l, widthCm: offer.dims.w, heightCm: offer.dims.h } : {}),
    declaredValue: offer.goodsTotal,
  };
  try {
    const q = zoneTariff.quoteParcel(tariff, parcel,
      { regionId: origin.regionId, districtId: origin.districtId || '' },
      { regionId: dest.regionId, districtId: dest.districtId || '' },
      { dimsOptional: true });
    return { ...base, fee: q.customerPrice, reason: null, fromPrice: !known, tariffVersion: q.tariffVersion };
  } catch (e) {
    const reason = (e && e.details && e.details.reason) || REASONS.TARIFF_ERROR;
    return { ...base, fee: null, reason };
  }
}

/**
 * Таклифга етказиш усулини танлаш (эга 2026-11-17):
 *   шу туман → маҳаллий, бошқа туман/вилоят → зона (чакана ва улгуржи бир хил); катта маиший техника → нарх сўрови.
 */
function deliveryFor({ offer, seller, buyer, tariffDoc, tariff, now }) {
  if (offer.kind === RETAIL && isLargeDeliveryLine({ market: offer.market, category: offer.category })) {
    return { method: null, fee: null, fromPrice: false, tariffVersion: null, reason: REASONS.DELIVERY_QUOTE_REQUIRED };
  }
  const sellerDistrict = (seller && seller.districtId) || '';
  if (!sellerDistrict && !(seller && seller.regionId)) {
    return { method: null, fee: null, fromPrice: false, tariffVersion: null, reason: REASONS.SELLER_LOCATION_MISSING };
  }
  if (sellerDistrict && sellerDistrict === buyer.districtId) {
    return localDelivery({ tariffDoc, from: seller, to: buyer, now });
  }
  return zoneDelivery({ tariff, origin: seller, dest: buyer, offer });
}

/**
 * Тартиб: етказиш нархи бор (жами) — жами бўйича ўсиш; кейин етказиш нархи йўқлар — товар суммаси бўйича.
 * Тенгликда: тўлиқ мос (кўпроқ сўз) олдин, кейин янгироқ. Реклама (`sponsored`) ИШТИРОК ЭТМАЙДИ.
 */
function rankOffers(offers) {
  return offers.slice().sort((a, b) => {
    const ah = a.total != null; const bh = b.total != null;
    if (ah !== bh) return ah ? -1 : 1;
    const av = ah ? a.total : a.goodsTotal; const bv = bh ? b.total : b.goodsTotal;
    if (av !== bv) return av - bv;
    if ((b.matched || 0) !== (a.matched || 0)) return (b.matched || 0) - (a.matched || 0);
    return (b.listedAt || 0) - (a.listedAt || 0);
  });
}

/** Мижозга қайтариладиган шакл (ички майдонлар/координаталар йўқ; ZONE номи кўрсатилмайди — 45). */
function publicOffer(o) {
  return {
    id: o.id,
    source: o.source,
    kind: o.kind,
    title: o.title,
    photoUrl: o.photoUrl,
    sellerName: o.sellerName,
    ownerPhone: o.ownerPhone,
    businessId: o.businessId || null,
    sellerDistrictId: o.sellerDistrictId || o.districtId || null,
    sellerRegionId: o.sellerRegionId || o.regionId || null,
    price: o.price,
    priceUnit: o.priceUnit || '',
    priceFrom: !!o.priceFrom,
    unit: o.unit || null,
    qty: o.qty,
    moq: o.moq || null,
    packLabel: o.packLabel || null,
    packsCount: o.packsCount || 0,
    goodsTotal: o.goodsTotal,
    delivery: {
      fee: o.delivery.fee,
      method: o.delivery.method,
      fromPrice: !!o.delivery.fromPrice,
      estimate: true,
      reason: o.delivery.reason,
      tariffVersion: o.delivery.tariffVersion,
    },
    total: o.total,
    totalFrom: o.total != null && (!!o.delivery.fromPrice || !!o.priceFrom),
    listedAt: o.listedAt,
    sponsored: !!o.sponsored,
    matchedAll: !!o.matchedAll,
  };
}

// ─────────────────────────────────────────────────────────────────────────
// FIRESTORE
// ─────────────────────────────────────────────────────────────────────────

function createPriceSearch({ db, now = () => new Date() }) {
  async function getAllMap(refs) {
    if (!refs.length) return new Map();
    const snaps = await db.getAll(...refs);
    return new Map(snaps.map((s) => [s.ref.path, s.exists ? (s.data() || {}) : null]));
  }

  /** Туман → вилоят (`geo_districts/{id}.regionId`) — сервер манбаси, клиент вилояти ишлатилмайди. */
  async function regionsFor(districtIds) {
    const ids = [...new Set(districtIds.filter((x) => x && GEO_ID_RE.test(x)))];
    const m = await getAllMap(ids.map((id) => db.collection('geo_districts').doc(id)));
    const out = new Map();
    for (const id of ids) {
      const d = m.get(`geo_districts/${id}`);
      if (d && typeof d.regionId === 'string' && d.regionId) out.set(id, d.regionId);
    }
    return out;
  }

  async function fetchCandidates(tokens, limit) {
    const [retailSnap, wsSnap] = await Promise.all([
      db.collection(SRC_RETAIL)
        .where('status', '==', 'active')
        .where('searchTokens', 'array-contains-any', tokens)
        .orderBy('createdAt', 'desc')
        .limit(limit)
        .get(),
      // Индекс керак эмас (тенглик + array-contains-any, тартибсиз — бир майдонли индекслар бирлашади).
      db.collection(SRC_WHOLESALE)
        .where('status', '==', 'active')
        .where('searchTokens', 'array-contains-any', tokens)
        .limit(limit)
        .get(),
    ]);
    return { retail: retailSnap.docs, wholesale: wsSnap.docs };
  }

  /** Сотувчи жойи: объект / ўз дўкони (аниқ private → тахминий area → эски pickup) / улгуржи сотувчи. */
  async function sellerPoints(offers) {
    const refs = [];
    const want = (ref) => { if (!refs.some((r) => r.path === ref.path)) refs.push(ref); };
    for (const o of offers) {
      if (o.kind === WHOLESALE) {
        if (PHONE_RE.test(o.ownerPhone)) want(db.collection('wholesale_sellers').doc(o.ownerPhone));
      } else if (o.businessId) {
        want(db.collection('businesses').doc(o.businessId));
      } else if (PHONE_RE.test(o.ownerPhone)) {
        const shop = db.collection('tv_shops').doc(o.ownerPhone);
        want(shop);
        want(shop.collection('private').doc('pickup'));
      }
    }
    const m = await getAllMap(refs);
    const points = new Map();
    for (const o of offers) {
      let p = null;
      if (o.kind === WHOLESALE) {
        const s = m.get(`wholesale_sellers/${o.ownerPhone}`);
        if (s) p = { lat: s.lat, lng: s.lng, districtId: str(s.districtId, 64) || o.districtId, regionId: str(s.regionId, 64) };
      } else if (o.businessId) {
        const b = m.get(`businesses/${o.businessId}`);
        if (b && String(b.status || 'active') === 'active' && b.online !== true) {
          p = { lat: b.lat, lng: b.lng, districtId: str(b.districtId, 64) || o.districtId, regionId: str(b.regionId, 64) || o.regionId };
        }
      } else {
        const shop = m.get(`tv_shops/${o.ownerPhone}`) || {};
        if (String(shop.status || 'active') === 'blocked') { points.set(o, 'blocked'); continue; }
        const priv = m.get(`tv_shops/${o.ownerPhone}/private/pickup`) || {};
        let lat = null; let lng = null;
        if (validLatLng(priv.lat, priv.lng)) { lat = priv.lat; lng = priv.lng; } else if (validLatLng(shop.areaLat, shop.areaLng)) {
          lat = shop.areaLat; lng = shop.areaLng;
        } else if (validLatLng(shop.pickupLat, shop.pickupLng)) { lat = shop.pickupLat; lng = shop.pickupLng; }
        p = { lat, lng, districtId: o.districtId, regionId: o.regionId };
      }
      points.set(o, p);
    }
    // Вилоят йўқ бўлса — тумандан (сервер манбаси).
    const missing = [...points.values()].filter((p) => p && p !== 'blocked' && !p.regionId && p.districtId).map((p) => p.districtId);
    const reg = await regionsFor(missing);
    for (const p of points.values()) if (p && p !== 'blocked' && !p.regionId && p.districtId) p.regionId = reg.get(p.districtId) || '';
    return points;
  }

  /**
   * @param {{query:string, buyer:{districtId:string, lat?:number, lng?:number}, fetchLimit?:number, resultLimit?:number}} p
   */
  async function search(p) {
    const { words, tokens } = parseQuery(p.query);
    if (!words.length) {
      const e = new Error('query_too_short'); e.code = 'invalid-argument'; e.reason = 'query_too_short'; throw e;
    }
    const nowDate = now();
    const nowMs = nowDate.getTime();
    const buyerDistrict = str(p.buyer && p.buyer.districtId, 64);
    const reg = await regionsFor([buyerDistrict]);
    if (!reg.get(buyerDistrict)) {
      const e = new Error('location_required'); e.code = 'invalid-argument'; e.reason = 'location_required'; throw e;
    }
    const buyer = {
      districtId: buyerDistrict,
      regionId: reg.get(buyerDistrict),
      lat: validLatLng(p.buyer.lat, p.buyer.lng) ? p.buyer.lat : null,
      lng: validLatLng(p.buyer.lat, p.buyer.lng) ? p.buyer.lng : null,
    };
    const fetchLimit = Math.min(Math.max(isPosInt(p.fetchLimit) ? p.fetchLimit : FETCH_LIMIT_DEFAULT, 1), FETCH_LIMIT_MAX);
    const resultLimit = Math.min(Math.max(isPosInt(p.resultLimit) ? p.resultLimit : RESULT_LIMIT_DEFAULT, 1), FETCH_LIMIT_MAX);

    const cand = await fetchCandidates(tokens, fetchLimit);
    let offers = [];
    for (const s of cand.retail) {
      const o = retailOfferFrom(s.id, s.data() || {}, nowMs);
      if (o) { o.matched = matchCount(words, s.data() || {}); offers.push(o); }
    }
    for (const s of cand.wholesale) {
      const o = wholesaleOfferFrom(s.id, s.data() || {});
      if (o) { o.matched = matchCount(words, s.data() || {}); offers.push(o); }
    }
    // Ҳамма сўз мос келганлар; бўлмаса — қисман (белгиланади).
    const full = offers.filter((o) => o.matched >= words.length);
    const partial = full.length === 0 && offers.length > 0;
    offers = (partial ? offers : full).map((o) => ({ ...o, matchedAll: !partial }));

    // Улгуржида туман сотувчи ҳужжатидан аниқланади — шу туман эҳтимоли бўлса тариф ўқилади (1 ўқиш).
    const needsLocal = offers.some((o) => o.kind === WHOLESALE || (o.districtId && o.districtId === buyer.districtId));
    const [points, tariffDocSnap, tariff] = await Promise.all([
      sellerPoints(offers),
      needsLocal ? db.collection('settings').doc('restaurant_delivery').get() : Promise.resolve(null),
      zoneTariff.getActiveTariff(db),
    ]);
    const tariffDoc = tariffDocSnap && tariffDocSnap.exists ? (tariffDocSnap.data() || {}) : {};
    const out = [];
    for (const o of offers) {
      const seller = points.get(o);
      if (seller === 'blocked') continue;
      const delivery = seller
        ? deliveryFor({ offer: o, seller, buyer, tariffDoc, tariff, now: nowDate })
        : { method: null, fee: null, fromPrice: false, tariffVersion: null, reason: REASONS.SELLER_LOCATION_MISSING };
      const total = delivery.fee != null && Number.isSafeInteger(o.goodsTotal + delivery.fee) ? o.goodsTotal + delivery.fee : null;
      out.push({ ...o, sellerDistrictId: seller ? seller.districtId : o.districtId, sellerRegionId: seller ? seller.regionId : o.regionId, delivery, total });
    }
    const ranked = rankOffers(out).slice(0, resultLimit).map(publicOffer);
    return {
      offers: ranked,
      partial,
      counts: {
        retailCandidates: cand.retail.length,
        wholesaleCandidates: cand.wholesale.length,
        returned: ranked.length,
        withDelivery: ranked.filter((x) => x.delivery.fee != null).length,
      },
      zoneTariffVersion: tariff ? tariff.version || null : null,
      zoneTariffActive: !!tariff,
    };
  }

  return { search };
}

/** Структуравий log учун uid хеши (телефон log'га чиқмайди — 24, 40-қоида). */
function uidHash(uid) {
  return crypto.createHash('sha256').update(String(uid || '')).digest('hex').slice(0, 10);
}

module.exports = {
  createPriceSearch,
  parseQuery,
  matchCount,
  retailOfferFrom,
  wholesaleOfferFrom,
  cheapestWholesaleOption,
  localDelivery,
  zoneDelivery,
  deliveryFor,
  rankOffers,
  publicOffer,
  uidHash,
  REASONS,
  RETAIL,
  WHOLESALE,
  MAX_QUERY_CHARS,
  FETCH_LIMIT_DEFAULT,
};
