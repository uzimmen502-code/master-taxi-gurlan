'use strict';

/**
 * ОНЛАЙН ДЎКОН ҚИДИРУВИ (эга қарори 2026-10-25, 4-босқич): мавжуд глобал қидирув индекси `search_index`га
 * (янги тизим эмас, 4-банд) маҳсулот (`shop_item`) ва дўкон (`shop`: онлайн дўкон номи ва йўналишлар) ёзилади.
 *
 *  • `tv_shop_items/{id}` → `shop_item_<id>`; маҳсулотнинг ўзига ҳам `searchTokens` ёзилади — Аҳоли бозори
 *    қидируви охирги 80 та билан чекланмасин (`searchTokens array-contains`, автоматик индекс). Токенни сервер
 *    ҳисоблайди (18-банд): мижоз ёзиб қўйган «бегона» токен кейинги ёзувда тузатилади.
 *  • `tv_shops/{phone}` → `shop_<phone>` (номи); `businesses/{id}` → `shop_<id>` (йўналиш/филиал номи).
 *  • `target: {ownerPhone, businessId}` — натижа айнан шу онлайн дўконни ва йўналишни очади (филиал → отаси).
 *  • Блокланган/ўчирилган/номсиз — `active: false` (қидирувда чиқмайди); ҳужжат ўчирилса — индекс ёзуви ўчади.
 *
 * Алгоритм битта жойда: `search_tokens.js`.
 */

const { buildSearchIndexTokens } = require('./search_tokens');

const SHOP_KEYWORDS = Object.freeze(['дўкон', 'dokon', "do'kon", 'магазин', 'бозор', 'bozor']);
const digits = (v) => String(v == null ? '' : v).replace(/\D/g, '');
const s = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

function canonicalPhone(v) {
  const d = digits(v);
  if (d.length === 9) return `998${d}`;
  return d;
}

function sameTokens(a, b) {
  if (!Array.isArray(a) || a.length !== b.length) return false;
  for (let i = 0; i < b.length; i += 1) if (a[i] !== b[i]) return false;
  return true;
}

/** Маҳсулот токенлари (номи + тавсифи) — маҳсулот ҳужжати ва индекс учун бир хил. */
function shopItemTokens(d) {
  return buildSearchIndexTokens(s(d.title, 200), s(d.description, 2000));
}

function shopItemToSearchEntry(id, d) {
  const title = s(d.title, 160);
  const photos = Array.isArray(d.photoUrls) ? d.photoUrls : [];
  const cover = s(photos[0] || d.photoUrl, 500);
  const owner = canonicalPhone(d.ownerPhone);
  return {
    type: 'shop_item',
    moduleId: 'cheap_products_home',
    sourceCollection: 'tv_shop_items',
    sourceId: id,
    title,
    subtitle: s(d.ownerName, 120) || 'Онлайн дўкон',
    price: Number.isInteger(d.price) && d.price > 0 ? d.price : null,
    imageUrl: cover,
    iconKey: 'shop',
    keywords: [...SHOP_KEYWORDS],
    searchTokens: shopItemTokens(d),
    priorityBoost: 0,
    active: d.status === 'active' && title.length > 0 && owner.length === 12,
    ...(s(d.districtId, 64) ? { geo: { districtId: s(d.districtId, 64) } } : {}),
    target: { ownerPhone: owner, businessId: s(d.businessId, 128) },
  };
}

function tvShopToSearchEntry(phone, d) {
  const name = s(d.name, 160);
  return {
    type: 'shop',
    moduleId: 'cheap_products_home',
    sourceCollection: 'tv_shops',
    sourceId: phone,
    title: name,
    subtitle: 'Онлайн дўкон',
    imageUrl: '',
    iconKey: 'shop',
    keywords: [...SHOP_KEYWORDS],
    priorityBoost: 1,
    active: name.length >= 2 && d.status !== 'blocked' && canonicalPhone(phone).length === 12,
    target: { ownerPhone: canonicalPhone(phone), businessId: '' },
  };
}

function businessToSearchEntry(id, d) {
  const name = s(d.name, 160);
  const owner = canonicalPhone(d.ownerId);
  return {
    type: 'shop',
    moduleId: 'cheap_products_home',
    sourceCollection: 'businesses',
    sourceId: id,
    title: name,
    subtitle: s(d.address, 200) || s(d.subtype, 200) || 'Онлайн дўкон',
    imageUrl: '',
    iconKey: 'shop',
    keywords: [...SHOP_KEYWORDS, s(d.subtype, 60)].filter(Boolean),
    priorityBoost: 1,
    // Эгасиз (админ қўшган) объектнинг онлайн дўкони йўқ — қидирувдан дўкон очилмайди.
    active: name.length >= 2 && d.status !== 'blocked' && owner.length === 12,
    ...(s(d.districtId, 64) ? { geo: { districtId: s(d.districtId, 64) } } : {}),
    target: { ownerPhone: owner, businessId: s(d.branchOf, 128) || id },
  };
}

/**
 * КАФЕ-РЕСТОРАН / УЙ ОШПАЗИ (2026-10-25, Agent C): `restaurants/{rid}` → `restaurant_<rid>` (тур `restaurant`,
 * модул `restaurants`). Натижа очадиган ресторан — `sourceId` (манба ва очиладиган объект бир хил; дўкондаги каби
 * филиал→ота алмашинуви йўқ, шунинг учун `target` ёзилмайди — `upsertSearchIndexEntry` ўзгармайди).
 * Фақат `approved`, номли ва намуна ЭМАС (`isDemo` — намуна рўйхатда «бўш эмас» деб кўрсатилади, қидирувда эса
 * мижозни алдамасин, PROPOSED) ресторан фаол; тўхтатилса/ёпилса — `active: false`; ўчирилса — ёзув ўчади.
 * Манзил ва телефон индексга ЁЗИЛМАЙДИ (уй ошпазининг манзили — уйи, 40-банд).
 */
const RESTAURANT_KEYWORDS = Object.freeze(['кафе', 'kafe', 'ресторан', 'restoran', 'овқат', 'ovqat', 'таом', 'taom', 'меню', 'menyu']);
const HOME_COOK_KEYWORDS = Object.freeze(['уй овқати', 'uy ovqati', 'ошпаз', 'oshpaz', 'овқат', 'ovqat', 'таом', 'taom']);

function isHomeCookRestaurant(d) {
  if (['home', 'cafe', 'restaurant', 'chaikhana'].includes(d.venueType)) return d.venueType === 'home';
  return d.legalType === 'individual';
}

function restaurantToSearchEntry(id, d) {
  const name = s(d.name, 160);
  const home = isHomeCookRestaurant(d);
  const tags = Array.isArray(d.cuisineTags) ? d.cuisineTags.map((x) => s(x, 30)).filter(Boolean).slice(0, 3) : [];
  return {
    type: 'restaurant',
    moduleId: 'restaurants',
    sourceCollection: 'restaurants',
    sourceId: id,
    title: name,
    subtitle: home ? 'Уй ошпази' : 'Кафе-ресторан',
    imageUrl: s(d.logoUrl || d.coverUrl, 500),
    iconKey: 'restaurant',
    keywords: [...(home ? HOME_COOK_KEYWORDS : RESTAURANT_KEYWORDS), ...tags],
    priorityBoost: 1,
    active: d.status === 'approved' && d.isDemo !== true && name.length >= 2,
  };
}

/** Ресторан ҳужжатидан ИНДЕКСга таъсир қиладиган қисм (рейтинг, пауза, `publicId` ва ҳ.к. — кирмайди). */
function restaurantSearchFingerprint(d) {
  if (!d) return 'null';
  const ts = d.searchIndexedAt && typeof d.searchIndexedAt.toMillis === 'function' ? d.searchIndexedAt.toMillis() : null;
  return JSON.stringify([
    d.status || '', d.name || '', d.logoUrl || '', d.coverUrl || '', d.venueType || '', d.legalType || '',
    Array.isArray(d.cuisineTags) ? d.cuisineTags : [], d.isDemo === true, ts,
  ]);
}

/**
 * Битта ҳужжатни индекслаш (триггер ва бир марталик тўлдириш учун бир хил). [apply] `false` — фақат ҳисоблаш.
 * Маҳсулотда `searchTokens` фақат фарқ қилса ёзилади (триггер ўзини чексиз чақирмайди).
 */
async function indexShopDoc(kind, id, data, deps, { apply = true } = {}) {
  const { upsertSearchIndexEntry, deleteSearchIndexEntry, db } = deps;
  if (kind === 'item') {
    if (!data) {
      if (apply) await deleteSearchIndexEntry('shop_item', id);
      return { entry: null, tokensUpdated: false };
    }
    const entry = shopItemToSearchEntry(id, data);
    const tokensUpdated = !sameTokens(data.searchTokens, entry.searchTokens);
    if (apply) {
      if (tokensUpdated) await db.collection('tv_shop_items').doc(id).update({ searchTokens: entry.searchTokens });
      await upsertSearchIndexEntry(entry);
    }
    return { entry, tokensUpdated };
  }
  if (kind === 'restaurant') {
    if (!data) {
      if (apply) await deleteSearchIndexEntry('restaurant', id);
      return { entry: null, tokensUpdated: false };
    }
    const entry = restaurantToSearchEntry(id, data);
    if (apply) await upsertSearchIndexEntry(entry);
    return { entry, tokensUpdated: false };
  }
  if (!data) {
    if (apply) await deleteSearchIndexEntry('shop', id);
    return { entry: null, tokensUpdated: false };
  }
  const entry = kind === 'shop' ? tvShopToSearchEntry(id, data) : businessToSearchEntry(id, data);
  if (apply) await upsertSearchIndexEntry(entry);
  return { entry, tokensUpdated: false };
}

/** Триггерлар (v2, бошқа `search_index` триггерлари билан бир хил минтақа). */
function attachShopSearchIndex(exportsObj, deps) {
  const { onDocumentWritten } = deps;
  const log = (o) => console.log(JSON.stringify({ module: 'shop_search_index', ...o }));
  const handler = (kind, param) => async (event) => {
    const id = event.params[param];
    const after = event.data && event.data.after;
    const data = after && after.exists ? (after.data() || {}) : null;
    try {
      const out = await indexShopDoc(kind, id, data, deps);
      log({ action: `index_${kind}`, result: data ? (out.entry && out.entry.active ? 'active' : 'inactive') : 'deleted' });
    } catch (e) {
      console.error(JSON.stringify({
        module: 'shop_search_index', action: `index_${kind}`, result: 'error', errorCode: 'SHOP_SEARCH_INDEX_FAILED',
        message: String((e && e.message) || e).slice(0, 200),
      }));
    }
  };
  exportsObj.onSearchIndexShopItemWrite = onDocumentWritten(
    { document: 'tv_shop_items/{id}', region: 'europe-west1' }, handler('item', 'id'),
  );
  exportsObj.onSearchIndexTvShopWrite = onDocumentWritten(
    { document: 'tv_shops/{phone}', region: 'europe-west1' }, handler('shop', 'phone'),
  );
  exportsObj.onSearchIndexBusinessWrite = onDocumentWritten(
    { document: 'businesses/{id}', region: 'europe-west1' }, handler('business', 'id'),
  );
  // Ресторан: рейтинг/пауза/таймаут каби тез-тез ўзгарадиган майдонлар индексга таъсир қилмайди — фақат
  // индексга кирадиган қисм ўзгарганда ёзилади (36, 37-банд).
  const restaurantHandler = handler('restaurant', 'rid');
  exportsObj.onSearchIndexRestaurantWrite = onDocumentWritten(
    { document: 'restaurants/{rid}', region: 'europe-west1' },
    async (event) => {
      const b = event.data && event.data.before;
      const a = event.data && event.data.after;
      const before = b && b.exists ? (b.data() || {}) : null;
      const after = a && a.exists ? (a.data() || {}) : null;
      if (b && restaurantSearchFingerprint(before) === restaurantSearchFingerprint(after)) {
        log({ action: 'index_restaurant', result: 'skipped' });
        return;
      }
      await restaurantHandler(event);
    },
  );
}

module.exports = {
  attachShopSearchIndex, indexShopDoc, shopItemToSearchEntry, tvShopToSearchEntry, businessToSearchEntry, shopItemTokens,
  restaurantToSearchEntry, restaurantSearchFingerprint,
};
