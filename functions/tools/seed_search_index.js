/**
 * P0+P1 global search_index seed (services, routes, MFY, products, ads, bread, food, yuk).
 * Idempotent merge writes. Same payload shape as CF adminSeedSearchIndex.
 *
 *   node functions/tools/seed_search_index.js
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();
db.settings({ preferRest: true });

const MAX_TOKENS = 64;

function docId(type, sourceId) {
  return `${type}_${String(sourceId)}`.slice(0, 700);
}

function tokens(...parts) {
  const text = parts.filter(Boolean).join(' ').toLowerCase();
  const words = text.split(/[^0-9a-zа-яёўқғҳʻʼ']+/i).filter((w) => w && w.length >= 2);
  const out = new Set();
  for (const w of words) {
    out.add(w);
    if (out.size >= MAX_TOKENS) break;
  }
  return Array.from(out).slice(0, MAX_TOKENS);
}

async function upsert(entry) {
  const type = String(entry.type || '').trim();
  const sourceId = String(entry.sourceId || '').trim();
  if (!type || !sourceId) return;
  const keywords = Array.isArray(entry.keywords)
    ? entry.keywords.map((k) => String(k || '').trim().toLowerCase()).filter(Boolean).slice(0, 48)
    : [];
  const searchTokens = Array.isArray(entry.searchTokens) && entry.searchTokens.length
    ? entry.searchTokens.slice(0, MAX_TOKENS)
    : tokens(entry.title, entry.subtitle, ...keywords, entry.geo && entry.geo.from, entry.geo && entry.geo.to);
  const payload = {
    type,
    moduleId: String(entry.moduleId || '').trim(),
    sourceCollection: String(entry.sourceCollection || '').trim(),
    sourceId,
    title: String(entry.title || '').trim().slice(0, 160),
    subtitle: String(entry.subtitle || '').trim().slice(0, 200),
    imageUrl: String(entry.imageUrl || '').trim(),
    iconKey: String(entry.iconKey || '').trim(),
    keywords,
    searchTokens,
    priorityBoost: Math.trunc(Number(entry.priorityBoost) || 0),
    active: entry.active !== false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (entry.price != null && Number.isFinite(Number(entry.price))) {
    payload.price = Math.trunc(Number(entry.price));
  }
  if (entry.geo && typeof entry.geo === 'object') {
    const geo = {};
    if (entry.geo.from) geo.from = String(entry.geo.from).trim();
    if (entry.geo.to) geo.to = String(entry.geo.to).trim();
    if (entry.geo.districtId) geo.districtId = String(entry.geo.districtId).trim();
    if (Object.keys(geo).length) payload.geo = geo;
  }
  await db.collection('search_index').doc(docId(type, sourceId)).set(payload, { merge: true });
}

function productEntry(id, d) {
  const name = String(d.name || '').trim();
  const urls = Array.isArray(d.imageUrls) ? d.imageUrls : [];
  const kind = String(d.goodsKind || '').trim();
  const keywords = ['ава', 'дукон', 'дўкон', 'ava', 'store', 'платформа'];
  if (kind === 'food') keywords.push('озиқ', 'oziq', 'food');
  if (kind === 'non_food') keywords.push('но-озиқ', 'non_food');
  return {
    type: 'platform_product',
    moduleId: 'platform',
    sourceCollection: 'platform_products',
    sourceId: id,
    title: name,
    subtitle: 'AVA дўкони',
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: String((urls[0] || d.imageUrl || '')).trim(),
    iconKey: 'shop',
    keywords,
    priorityBoost: 0,
    active: d.active !== false && name.length > 0,
  };
}

function adEntry(id, d) {
  const adType = String(d.type || '').trim();
  const isMarket = adType === 'cheap_product';
  const isJob = ['work', 'service', 'ad'].includes(adType);
  if (!isMarket && !isJob) return null;
  const title = String(d.title || '').trim() || String(d.text || '').trim().slice(0, 80);
  const status = String(d.status || '');
  const active = status === 'active' && title.length > 0;
  const desc = String(d.description || d.text || '');
  const searchTokens = Array.isArray(d.searchTokens) && d.searchTokens.length
    ? d.searchTokens
    : tokens(title, desc);
  if (isMarket) {
    return {
      type: 'market_ad',
      moduleId: 'cheap_products_home',
      sourceCollection: 'ads',
      sourceId: id,
      title,
      subtitle: 'Онлайн бозор',
      price: Math.trunc(Number(d.price) || 0),
      imageUrl: Array.isArray(d.imageUrls) && d.imageUrls[0] ? String(d.imageUrls[0]) : '',
      iconKey: 'shop',
      keywords: ['бозор', 'bozor', 'эълон', 'сотиш'],
      searchTokens,
      priorityBoost: 0,
      active,
    };
  }
  return {
    type: 'job',
    moduleId: 'jobs',
    sourceCollection: 'ads',
    sourceId: id,
    title,
    subtitle: 'ИШ ЭЪЛОН',
    imageUrl: '',
    iconKey: 'job',
    keywords: ['иш', 'ish', 'вакансия', 'эълон', adType],
    searchTokens,
    priorityBoost: 0,
    active,
  };
}

const SERVICES = [
  { id: 'local_taxi', moduleId: 'local_taxi', title: 'Маҳаллий такси', subtitle: 'Туман ичида такси', iconKey: 'taxi', keywords: ['такси', 'taxi', 'маҳаллий', 'махаллий', 'йўловчи'], boost: 22 },
  { id: 'intercity', moduleId: 'intercity', title: 'Шаҳарлараро такси', subtitle: 'Шаҳарлараро йўналиш', iconKey: 'taxi', keywords: ['такси', 'taxi', 'шаҳарлараро', 'тошкент', 'йўловчи'], boost: 24 },
  { id: 'marshrut', moduleId: 'marshrut', title: 'Маршрут такси', subtitle: 'Маршрут бўйича', iconKey: 'taxi', keywords: ['такси', 'taxi', 'маршрут', 'marshrut'], boost: 20 },
  { id: 'yuk_birja', moduleId: 'yuk_birja', title: 'Юк биржа', subtitle: 'Юк ташиш', iconKey: 'yuk', keywords: ['юк', 'yuk', 'биржа', 'груз', 'такси'], boost: 18 },
  { id: 'platform', moduleId: 'platform', title: 'AVA дўкони', subtitle: 'Платформа дўкони', iconKey: 'shop', keywords: ['ава', 'ava', 'дўкон', 'дукон', 'магазин', 'платформа'], boost: 20 },
  { id: 'food', moduleId: 'food', title: 'Овқат', subtitle: 'Таом буюртма', iconKey: 'food', keywords: ['овқат', 'ovqat', 'таом', 'кафе', 'емак'], boost: 20 },
  { id: 'bread', moduleId: 'bread', title: 'Нон', subtitle: 'Нон буюртма', iconKey: 'bread', keywords: ['нон', 'non', 'патир', 'чўрек'], boost: 20 },
  { id: 'jobs', moduleId: 'jobs', title: 'ИШ ЭЪЛОН', subtitle: 'Иш ва хизмат эълонлари', iconKey: 'job', keywords: ['иш', 'ish', 'вакансия', 'эълон', 'лаборант'], boost: 22 },
  { id: 'cheap_products_home', moduleId: 'cheap_products_home', title: 'Онлайн бозор', subtitle: 'Арзон маҳсулотлар', iconKey: 'shop', keywords: ['бозор', 'bozor', 'сотиш', 'магазин'], boost: 18 },
  { id: 'milk', moduleId: 'milk', title: 'Сут қабул', subtitle: 'Сут ва қишлоқ маҳсулотлари', iconKey: 'milk', keywords: ['сут', 'sut', 'қатиқ', 'тухум'], boost: 16 },
  { id: 'oil_change', moduleId: 'oil_change', title: 'Мой алмаштириш', subtitle: 'Авто сервис', iconKey: 'oil', keywords: ['мой', 'oil', 'авто', 'машина'], boost: 14 },
  { id: 'sell', moduleId: 'sell', title: 'Сотиш', subtitle: 'Сотиш маркази', iconKey: 'sell', keywords: ['сотиш', 'sotish', 'продаж'], boost: 14 },
  { id: 'carpet_wash', moduleId: 'carpet_wash', title: 'Гилам ювиш', subtitle: 'Гилам хизмати', iconKey: 'carpet', keywords: ['гилам', 'gilam', 'ювиш'], boost: 12 },
];

const HUBS = ['Гурлан', 'Урганч', 'Хива'];
const DESTS = ['Тошкент', 'Самарқанд', 'Бухоро', 'Навоий', 'Нукус', 'Андижон', 'Фарғона', 'Қарши', 'Термиз', 'Урганч', 'Хива'];

const GURLAN_MFY = [
  'Ёрмиш МФЙ', 'Обод МФЙ', 'Ишонч МФЙ', 'Дўстлик МФЙ', 'Навбаҳор МФЙ',
  'Чинобод МФЙ', 'Боғишамол МФЙ', 'Марифат МФЙ', 'Мевазор МФЙ', 'Дўсимбий МФЙ',
  'Фидокор МФЙ', 'Навбир-ёп МФЙ', 'Нукус МФЙ', 'Нурафшон МФЙ', 'Қатариқ МФЙ',
  'Чаккалар МФЙ', 'Зиёкор МФЙ', 'Сахтиён МФЙ', 'Янги боғ МФЙ', 'Эсабий МФЙ',
  'Қангли МФЙ', 'Ватанпарвар МФЙ', 'Марбугат МФЙ', 'Бирлашган МФЙ', 'Гулшан МФЙ',
  'Бўзқалъа МФЙ', 'Олчин МФЙ', 'Ўйилма МФЙ', 'Деҳқонобод МФЙ', 'Тахтакўпир МФЙ',
  'Мойли МФЙ', 'Шанғи МФЙ', 'Олға МФЙ', 'Янги аср МФЙ', 'Болдоқли МФЙ',
  'Шодлик МФЙ', 'Эшимжирон МФЙ', 'Жалойир МФЙ', 'Пахтачи МФЙ', 'Нурли йўл МФЙ',
  'Совунчи МФЙ', 'Пахтакор МФЙ', 'Деҳқон МФЙ', 'Беш уй МФЙ', 'Боғистон МФЙ',
  'Оққум МФЙ', 'Нуробод МФЙ', 'Дўстлик боғи МФЙ',
];

function breadEntry(id, d) {
  const name = String(d.name || '').trim();
  return {
    type: 'bread_product',
    moduleId: 'bread',
    sourceCollection: 'bread_products',
    sourceId: id,
    title: name,
    subtitle: 'Нон',
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: String(d.imageUrl || d.image || '').trim(),
    iconKey: 'bread',
    keywords: ['нон', 'non', 'патир', 'чўрек', String(d.type || '')],
    priorityBoost: 4,
    active: name.length > 0,
  };
}

function foodEntry(id, d) {
  const name = String(d.name || '').trim();
  const category = String(d.category || '').trim();
  return {
    type: 'food_product',
    moduleId: 'food',
    sourceCollection: 'food_catalog',
    sourceId: id,
    title: name,
    subtitle: category || 'Овқат',
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: String(d.imageUrl || '').trim(),
    iconKey: 'food',
    keywords: ['овқат', 'ovqat', 'таом', 'кафе', category],
    priorityBoost: 4,
    active: name.length > 0,
  };
}

function yukEntry(id, d) {
  const from = String(d.from || '').trim();
  const to = String(d.to || '').trim();
  const status = String(d.status || '').trim();
  const cargo = String(d.cargo || '').trim();
  const vehicle = String(d.vehicleType || '').trim();
  const listingType = String(d.type || '').trim();
  let expiresMs = 0;
  const e = d.expiresAt;
  if (e && typeof e.toMillis === 'function') expiresMs = e.toMillis();
  else if (e && e._seconds != null) expiresMs = Number(e._seconds) * 1000;
  else if (e) {
    const parsed = Date.parse(String(e));
    expiresMs = Number.isFinite(parsed) ? parsed : 0;
  }
  const notExpired = !expiresMs || expiresMs > Date.now();
  const title = from && to ? `${from} → ${to}` : (cargo || vehicle || 'Юк эълони');
  return {
    type: 'yuk_listing',
    moduleId: 'yuk_birja',
    sourceCollection: 'yuk_listings',
    sourceId: id,
    title,
    subtitle: listingType === 'truck' ? (vehicle || 'Юк машина') : (cargo || 'Юк'),
    price: Math.trunc(Number(d.price) || 0),
    imageUrl: '',
    iconKey: 'yuk',
    keywords: ['юк', 'yuk', 'биржа', listingType, vehicle, cargo, from, to],
    geo: { from, to },
    priorityBoost: 6,
    active: status === 'active' && notExpired && title.length > 0,
  };
}

async function main() {
  let services = 0;
  let routes = 0;
  let places = 0;
  let products = 0;
  let ads = 0;
  let bread = 0;
  let food = 0;
  let yuk = 0;

  for (const s of SERVICES) {
    await upsert({
      type: 'service',
      moduleId: s.moduleId,
      sourceCollection: 'seed',
      sourceId: s.id,
      title: s.title,
      subtitle: s.subtitle,
      iconKey: s.iconKey,
      keywords: s.keywords,
      priorityBoost: s.boost,
      active: true,
    });
    services += 1;
  }

  for (const from of HUBS) {
    for (const to of DESTS) {
      if (from === to) continue;
      const sid = `${from}_${to}`.replace(/\s+/g, '_');
      await upsert({
        type: 'intercity_route',
        moduleId: 'intercity',
        sourceCollection: 'seed',
        sourceId: sid,
        title: `${from} → ${to}`,
        subtitle: 'Шаҳарлараро такси',
        iconKey: 'taxi',
        keywords: ['такси', 'taxi', 'шаҳарлараро', from, to, `${to}га`, 'йўловчи'],
        geo: { from, to },
        priorityBoost: 10,
        active: true,
      });
      routes += 1;
    }
  }

  for (const mfy of GURLAN_MFY) {
    const sid = mfy.replace(/\s+/g, '_');
    await upsert({
      type: 'local_place',
      moduleId: 'local_taxi',
      sourceCollection: 'seed_mfy',
      sourceId: sid,
      title: mfy,
      subtitle: 'Гурлан · маҳаллий такси',
      iconKey: 'taxi',
      keywords: ['такси', 'taxi', 'мфй', 'mfy', 'маҳалла', 'гурлан', 'gurlan', mfy],
      geo: { districtId: 'gurlan', from: mfy },
      priorityBoost: 8,
      active: true,
    });
    places += 1;
  }

  const prodSnap = await db.collection('platform_products').limit(2000).get();
  for (const doc of prodSnap.docs) {
    await upsert(productEntry(doc.id, doc.data() || {}));
    products += 1;
  }

  const adsSnap = await db.collection('ads').limit(2000).get();
  for (const doc of adsSnap.docs) {
    const entry = adEntry(doc.id, doc.data() || {});
    if (!entry) continue;
    await upsert(entry);
    ads += 1;
  }

  const breadSnap = await db.collection('bread_products').limit(500).get();
  for (const doc of breadSnap.docs) {
    await upsert(breadEntry(doc.id, doc.data() || {}));
    bread += 1;
  }

  const foodSnap = await db.collection('food_catalog').limit(500).get();
  for (const doc of foodSnap.docs) {
    await upsert(foodEntry(doc.id, doc.data() || {}));
    food += 1;
  }

  const yukSnap = await db.collection('yuk_listings').limit(500).get();
  for (const doc of yukSnap.docs) {
    await upsert(yukEntry(doc.id, doc.data() || {}));
    yuk += 1;
  }

  console.log(JSON.stringify({
    ok: true, services, routes, places, products, ads, bread, food, yuk,
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
