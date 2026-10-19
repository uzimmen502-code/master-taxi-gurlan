/**
 * KAFE-RESTORAN — bo'limlar indeksi (S3, D-REST-16, docs/kafe_restoran_taklifi_uz.md §10.1, D-REST-33).
 *
 * Ega qarori (2026-10-19): bo'limlar (Arzon, Fast-fud, Milliy, Dunyo, Yengil, Bolalar, Nonushta, Tungi) —
 * qo'lda tanlanadigan kategoriya EMAS, taomdagi ma'lumotdan hosil bo'ladigan ko'rinishlar. Ega dizayn va
 * qulaylik bo'yicha tanlashni menga topshirdi: har taomga bitta tayyor INDEKS hujjati
 * (`restaurant_dish_index/{rid}_{iid}`) — mijoz bo'limni BITTA so'rov bilan oladi (`sections` +
 * `geo4`), har safar yuzlab restoran menyusini o'qimaydi (36, 37-qoida). `order_index` bilan bir fikr.
 *
 * Yagona manba (7-qoida): bo'limga KIRISH qoidasi FAQAT shu yerda (`sectionsOf`); klient `sections`
 * massivini o'qiydi va qoidani takrorlamaydi. Tartiblash (Yangi, Arzon pog'onasi) — klientda, parametrlari
 * `settings/restaurant_sections` da (admin o'zgartiradi, kodga qotirilmagan).
 *
 * Bo'limga kirish (PROPOSED qoidalar — ega faqat bo'lim ro'yxatini tasdiqlagan, 47-qoida):
 *   cheap     — porsiya soni bor (bir kishilik narx hisoblanadi)                       [D-REST-20: porsiya majburiy]
 *   national  — kuxna guruhi `national` (kuxna ham bor)                                [D-REST-16]
 *   world     — kuxna guruhi `world`                                                    [D-REST-16]
 *   light     — `light` tegi VA KBJU to'liq                                             [D-REST-16: KBJU yo'q taom ko'rinmaydi]
 *   kids / breakfast / night — mos teg                                                  [D-REST-17]
 *   fast      — restoranning `cuisineTags` ida `fastfood` bor  (PROPOSED: «Fast-fud» belgisi
 *               taom darajasida yo'q; ega tasdiqlamaguncha shu qoida)
 *   office    — restoran oldindan buyurtma oladi (`acceptsPreorder`) VA taomda miqdorga chegirma (`qtyTiers`) bor
 *               [D-REST-21: Ofis = oldindan buyurtma + miqdorga chegirma; guruh buyurtma/hisob-faktura alohida emas]  (PROPOSED)
 *   dastarxon — `dastarxon` tegi VA restoran oldindan buyurtma oladi [D-REST-21: Dastarxon oldindan buyurtmaga tayanadi]  (PROPOSED)
 *   seasonal  — mavsum tegi (ramadan, navruz, qurbon, newyear, wedding); QAYSI mavsum hozir ochiq ekani sanaga bog'liq
 *               (`settings/restaurant_seasons`, 10 kun oldin ochiladi) va KLIENTDA hal qilinadi — indeks sana o'tgani uchun
 *               qayta yozilmaydi (22-qoida: vaqt o'tishi trigger emas); indeksda `seasons` massivi turadi    [D-REST-22]
 *
 * Indeksga TAOM kiradi, agar: restoran `approved`, koordinatasi to'g'ri, taom `available !== false`,
 * narx butun 1..50 000 000 va kamida bitta bo'limga kiradi. Aks holda hujjat O'CHIRILADI.
 *
 * Triggerlar (hammasi idempotent, tranzaksiyada manbadan qayta hisoblaydi — ketma-ketlik buzilsa ham oxirgi
 * holat to'g'ri, 21, 22-qoida): taom yozildi/o'chirildi; restoran o'zgardi (status, nom, joy, teg, tayyorlash
 * vaqti, ish vaqti, pauza) → barcha taomlari qayta hisoblanadi; taom statistikasi (baho) o'zgardi.
 * Indeks hujjati o'zgarmagan bo'lsa YOZILMAYDI (keraksiz yozuv va trigger yo'q).
 *
 * Log: `module: restaurants`, `action: dish_index`, `restaurantId`, `itemId`, `result`; telefon/manzil yo'q (24, 40).
 */
'use strict';

const geoHash = require('./geo_hash');
const qtyTiers = require('./restaurant_qty_tiers');

const INDEX = 'restaurant_dish_index';
const RESTAURANTS = 'restaurants';
const MENU_ITEMS = 'menu_items';
const STATS = 'menu_item_stats';
const MODULE_ID = 'restaurants';

/** Indeks tuzilishi/qoidasi versiyasi — qoida o'zgarsa oshiriladi va qayta hisoblash (backfill) kerak. */
const INDEX_RULES_VERSION = 2;
const MAX_PRICE = 50000000;
/** Bitta restoran uchun qayta hisoblanadigan taomlarning eng ko'pi (himoya). */
const MAX_DISHES_PER_RESTAURANT = 500;
const FANOUT_CHUNK = 10;
/** Geohash uzunligi: klient `GeoHash.neighborsForRadius(precision: 4)` bilan so'raydi. */
const GEO_PRECISION = 4;

const SECTION = Object.freeze({
  cheap: 'cheap', fast: 'fast', national: 'national', world: 'world',
  light: 'light', kids: 'kids', breakfast: 'breakfast', night: 'night',
  office: 'office', dastarxon: 'dastarxon', seasonal: 'seasonal',
});
const SECTION_KEYS = Object.freeze(Object.values(SECTION));
const FAST_FOOD_TAG = 'fastfood';
/** Mavsum teglari = mavsum kalitlari (`settings/restaurant_seasons`); tartib klient/`rules` bilan bir xil. */
const SEASON_KEYS = Object.freeze(['ramadan', 'navruz', 'qurbon', 'newyear', 'wedding']);
const DASTARXON_TAG = 'dastarxon';
/** Taomga qo'yiladigan teglar (firestore.rules `dishFactsOk` va klient `DishTag.all` bilan bir xil). */
const DISH_TAGS = Object.freeze(['kids', 'breakfast', 'night', 'light', DASTARXON_TAG, ...SEASON_KEYS]);
const MAX_TAGS_PER_DISH = 4;

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

function intIn(v, lo, hi) {
  return typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi ? v : null;
}

/** Bir kishilik narx: `ceil(narx / porsiya)` — butun so'm. Klientdagi `DishFacts.pricePerPerson` bilan bir xil. */
function pricePerPerson(price, servings) {
  if (!Number.isInteger(price) || price <= 0 || !Number.isInteger(servings) || servings <= 0) return null;
  return Math.ceil(price / servings);
}

function validLatLng(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng)
      && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
      && (Math.abs(lat) > 1e-6 || Math.abs(lng) > 1e-6);
}

/** Taom faktlari: klientdagi `DishFacts.fromMap` kabi — noto'g'ri qiymat «yo'q». */
function factsOf(item) {
  const servings = intIn(item.servings, 1, 50);
  const weightG = intIn(item.weightG, 10, 5000);
  const kcal = intIn(item.kcal, 0, 5000);
  const protein = intIn(item.protein, 0, 500);
  const fat = intIn(item.fat, 0, 500);
  const carbs = intIn(item.carbs, 0, 500);
  const nutritionOk = kcal != null && protein != null && fat != null && carbs != null;
  const group = item.cuisineGroup;
  const cuisineId = item.cuisineId;
  const cuisineOk = (group === 'national' || group === 'world') && typeof cuisineId === 'string' && cuisineId.length > 0;
  const tags = Array.isArray(item.tags)
    ? [...new Set(item.tags.filter((t) => DISH_TAGS.includes(t)))].slice(0, MAX_TAGS_PER_DISH)
    : [];
  return {
    servings, weightG,
    nutrition: nutritionOk ? { kcal, protein, fat, carbs } : null,
    cuisine: cuisineOk ? { group, id: cuisineId } : null,
    tags,
  };
}

/** Taom qaysi bo'limlarga kiradi (bo'sh massiv — hech biriga). */
function sectionsOf(item, restaurant) {
  const f = factsOf(item || {});
  const out = [];
  const price = item && item.price;
  if (pricePerPerson(price, f.servings) != null) out.push(SECTION.cheap);
  const restTags = restaurant && Array.isArray(restaurant.cuisineTags) ? restaurant.cuisineTags : [];
  if (restTags.includes(FAST_FOOD_TAG)) out.push(SECTION.fast);
  if (f.cuisine && f.cuisine.group === 'national') out.push(SECTION.national);
  if (f.cuisine && f.cuisine.group === 'world') out.push(SECTION.world);
  if (f.tags.includes('light') && f.nutrition) out.push(SECTION.light);
  if (f.tags.includes('kids')) out.push(SECTION.kids);
  if (f.tags.includes('breakfast')) out.push(SECTION.breakfast);
  if (f.tags.includes('night')) out.push(SECTION.night);
  const preorder = !!restaurant && restaurant.acceptsPreorder === true;
  if (preorder && qtyTiers.sanitizeTiers(price, item && item.qtyTiers).length > 0) out.push(SECTION.office);
  if (preorder && f.tags.includes(DASTARXON_TAG)) out.push(SECTION.dastarxon);
  if (f.tags.some((t) => SEASON_KEYS.includes(t))) out.push(SECTION.seasonal);
  return out;
}

function nonNegInt(v) {
  return typeof v === 'number' && Number.isInteger(v) && v > 0 ? v : 0;
}

/**
 * Indeks hujjati (yoki `null` — taom indeksda bo'lmasligi kerak). Sof funksiya (testlanadi).
 * `item` — menyu hujjati, `restaurant` — restoran hujjati, `stats` — `menu_item_stats` hujjati (yoki null).
 */
function buildIndexDoc({ rid, iid, item, restaurant, stats }) {
  if (!item || !restaurant) return null;
  if (restaurant.status !== 'approved') return null;
  if (item.available === false) return null;
  const price = typeof item.price === 'number' && Number.isInteger(item.price) ? item.price : 0;
  if (price < 1 || price > MAX_PRICE) return null;
  const lat = Number(restaurant.lat);
  const lng = Number(restaurant.lng);
  if (!validLatLng(lat, lng)) return null;
  const sections = sectionsOf(item, restaurant);
  if (sections.length === 0) return null;

  const f = factsOf(item);
  const geohash = typeof restaurant.geohash === 'string' && restaurant.geohash.length >= GEO_PRECISION
    ? restaurant.geohash : geoHash.encode(lat, lng, 7);
  const pp = pricePerPerson(price, f.servings);
  const sum = nonNegInt(stats && stats.ratingSum);
  const count = nonNegInt(stats && stats.ratingCount);
  const doc = {
    v: INDEX_RULES_VERSION,
    restaurantId: rid, itemId: iid,
    name: str(item.name, 80), photoUrl: str(item.photoUrl, 500),
    price, sections, tags: f.tags,
    seasons: f.tags.filter((t) => SEASON_KEYS.includes(t)),
    restaurantName: str(restaurant.name, 80),
    restaurantLat: lat, restaurantLng: lng,
    geo4: geohash.slice(0, GEO_PRECISION),
    prepTimeMin: intIn(restaurant.prepTimeMin, 5, 180) || 20,
    ratingSum: count > 0 ? sum : 0, ratingCount: count,
  };
  if (pp != null) { doc.pricePerPerson = pp; doc.servings = f.servings; }
  if (f.weightG != null) doc.weightG = f.weightG;
  if (f.nutrition) Object.assign(doc, f.nutrition);
  if (f.cuisine) { doc.cuisineGroup = f.cuisine.group; doc.cuisineId = f.cuisine.id; }
  if (item.stopUntil) doc.stopUntil = item.stopUntil;
  if (item.createdAt) doc.listedAt = item.createdAt;
  if (restaurant.openingHours && typeof restaurant.openingHours === 'object') doc.openingHours = restaurant.openingHours;
  if (restaurant.pausedUntil) doc.pausedUntil = restaurant.pausedUntil;
  return doc;
}

/** Hujjatni solishtirish uchun barqaror qator (Timestamp → ms). */
function fingerprint(doc) {
  if (!doc) return 'null';
  const norm = (v) => {
    if (v && typeof v.toMillis === 'function') return { __ts: v.toMillis() };
    if (Array.isArray(v)) return v.map(norm);
    if (v && typeof v === 'object') {
      return Object.fromEntries(Object.keys(v).sort().map((k) => [k, norm(v[k])]));
    }
    return v;
  };
  return JSON.stringify(norm(doc));
}

/** Restoran hujjatidan INDEKSga ta'sir qiladigan qismlar (reyting va h.k. kirmaydi — ular indeksda yo'q). */
function restaurantFingerprint(r) {
  if (!r) return 'null';
  return fingerprint({
    status: r.status, name: r.name, lat: r.lat, lng: r.lng, geohash: r.geohash,
    cuisineTags: r.cuisineTags, prepTimeMin: r.prepTimeMin, openingHours: r.openingHours,
    acceptsPreorder: r.acceptsPreorder === true,
    pausedUntil: r.pausedUntil || null,
  });
}

function attachRestaurantDishIndex(exportsObj, deps) {
  const { functions, db } = deps;

  function log(level, fields) {
    (level === 'error' ? console.error : console.log)(JSON.stringify({ module: MODULE_ID, action: 'dish_index', ...fields }));
  }

  /**
   * Bitta taomning indeksini manbadan qayta hisoblaydi (tranzaksiya: o'qishlar yozishdan oldin).
   * Natija: 'written' | 'deleted' | 'unchanged'.
   */
  async function reindexDish(rid, iid) {
    const rRef = db.collection(RESTAURANTS).doc(rid);
    const iRef = rRef.collection(MENU_ITEMS).doc(iid);
    const sRef = rRef.collection(STATS).doc(iid);
    const xRef = db.collection(INDEX).doc(`${rid}_${iid}`);
    return db.runTransaction(async (t) => {
      const [r, i, s, x] = await Promise.all([t.get(rRef), t.get(iRef), t.get(sRef), t.get(xRef)]);
      const next = buildIndexDoc({
        rid, iid,
        item: i.exists ? i.data() : null,
        restaurant: r.exists ? r.data() : null,
        stats: s.exists ? s.data() : null,
      });
      if (!next) {
        if (!x.exists) return 'unchanged';
        t.delete(xRef);
        return 'deleted';
      }
      if (x.exists && fingerprint(x.data()) === fingerprint(next)) return 'unchanged';
      t.set(xRef, next);
      return 'written';
    });
  }

  /** Raw tranzaksiya xatosida (contention) 3 martagacha qayta uradi; mantiq xatosi yo'q — manbadan hisoblanadi. */
  async function reindexDishSafe(rid, iid) {
    let last = null;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        return await reindexDish(rid, iid);
      } catch (e) {
        last = e;
      }
    }
    throw last;
  }

  /** Restoranning barcha taomlari + indeksda qolib ketgan (taomi o'chgan) hujjatlar. */
  async function reindexRestaurant(rid) {
    const menu = await db.collection(RESTAURANTS).doc(rid).collection(MENU_ITEMS).limit(MAX_DISHES_PER_RESTAURANT + 1).get();
    if (menu.size > MAX_DISHES_PER_RESTAURANT) {
      log('error', { restaurantId: rid, result: 'truncated', errorCode: 'MENU_TOO_LARGE', limit: MAX_DISHES_PER_RESTAURANT });
    }
    const ids = menu.docs.slice(0, MAX_DISHES_PER_RESTAURANT).map((d) => d.id);
    const counts = { written: 0, deleted: 0, unchanged: 0 };
    for (let i = 0; i < ids.length; i += FANOUT_CHUNK) {
      const res = await Promise.all(ids.slice(i, i + FANOUT_CHUNK).map((id) => reindexDishSafe(rid, id)));
      res.forEach((x) => { counts[x] += 1; });
    }
    // Taomi o'chgan, lekin indeksi qolgan hujjatlar (trigger o'tkazib yuborgan bo'lsa).
    const stale = await db.collection(INDEX).where('restaurantId', '==', rid).limit(MAX_DISHES_PER_RESTAURANT + 50).get();
    const have = new Set(ids);
    for (const d of stale.docs) {
      const iid = (d.data() || {}).itemId;
      if (iid && !have.has(iid)) {
        counts[await reindexDishSafe(rid, iid)] += 1;
      }
    }
    return counts;
  }

  const wrap = (action, fn) => async (...args) => {
    const t0 = Date.now();
    const ctx = args[args.length - 1];
    const { rid, iid } = (ctx && ctx.params) || {};
    try {
      const out = await fn(...args);
      log('info', { restaurantId: rid, itemId: iid || undefined, trigger: action, result: 'ok', detail: out, durationMs: Date.now() - t0 });
    } catch (e) {
      // Indeks — hosila ma'lumot: xato manba hujjatni buzmaydi; keyingi o'zgarish yoki backfill tuzatadi.
      log('error', {
        restaurantId: rid, itemId: iid || undefined, trigger: action, result: 'error', errorCode: 'INDEX_FAILED',
        message: String((e && e.message) || e).slice(0, 160),
      });
    }
    return null;
  };

  exportsObj.onRestaurantMenuItemWritten = functions.firestore
    .document('restaurants/{rid}/menu_items/{iid}')
    .onWrite(wrap('menu_item', (change, context) => reindexDishSafe(context.params.rid, context.params.iid)));

  exportsObj.onRestaurantDishStatsWritten = functions.firestore
    .document('restaurants/{rid}/menu_item_stats/{iid}')
    .onWrite(wrap('stats', (change, context) => reindexDishSafe(context.params.rid, context.params.iid)));

  exportsObj.onRestaurantIndexSourceWritten = functions.firestore
    .document('restaurants/{rid}')
    .onWrite(wrap('restaurant', async (change, context) => {
      const before = change.before && change.before.exists ? change.before.data() : null;
      const after = change.after && change.after.exists ? change.after.data() : null;
      if (restaurantFingerprint(before) === restaurantFingerprint(after)) return { skipped: true };
      return reindexRestaurant(context.params.rid);
    }));

  return { reindexDish: reindexDishSafe, reindexRestaurant };
}

module.exports = {
  attachRestaurantDishIndex,
  buildIndexDoc,
  sectionsOf,
  pricePerPerson,
  fingerprint,
  restaurantFingerprint,
  SECTION,
  SECTION_KEYS,
  SEASON_KEYS,
  DISH_TAGS,
  MAX_TAGS_PER_DISH,
  DASTARXON_TAG,
  INDEX,
  INDEX_RULES_VERSION,
  GEO_PRECISION,
};
