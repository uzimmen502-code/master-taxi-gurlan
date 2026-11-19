/**
 * УЛГУРЖИ / ХИТОЙ — Excel орқали оммавий юклаш: СОФ қоидалар (Firestore'сиз, тестланади).
 * Эга қарори 2026-11-19 (A). Callable'лар: `wholesale_import.js`.
 *
 * ЯГОНА МАНБА (CLAUDE.md 7): чегаралар `firestore.rules` `wholesaleProductCreateOk` /
 * `wholesaleProductShippingOk` ва клиент модели (`wholesale_product.dart`, `shipping_dims.dart`,
 * `wholesale_pack.dart`) билан БИР ХИЛ. Бирортаси ўзгарса — шу ерни ҳам ўзгартиринг
 * (тест: `test/wholesale_import_rules.test.js`).
 *
 * Нарх (B, эга 2026-11-19): битта нарх — `priceTiers = [{ minQty: 1, price }]` + ихтиёрий
 * `minOrderQty` (сервер `effectiveMoq` = max(minOrderQty, биринчи поғона)). Пул — бутун сон (8-банд):
 * Улгуржида сўм, Хитойда маҳсулот валютасидаги бутун бирлик (мавжуд конвенция: `currency` '' | '$' | '¥').
 *
 * PROPOSED (эга тасдиқлагунча, 47-банд): unitMax 20, priceMax 10 000 000 000, deliveryDaysMax 365,
 * skuMax 64, SKU «#» билан бошланган қатор — намуна (ўқилмайди).
 */
'use strict';

const crypto = require('crypto');
const { words, toLatin, toCyrillic } = require('./market_search_tokens');

const LIMITS = Object.freeze({
  maxFileBytes: 5 * 1024 * 1024,
  maxUncompressedBytes: 60 * 1024 * 1024,
  maxRows: 500,
  maxUploadsPerDay: 10,
  skuMax: 64,
  titleMin: 3, // rules
  titleMax: 120, // rules
  descMin: 3, // rules
  descMax: 2000, // rules
  unitMax: 20, // PROPOSED
  priceMax: 10000000000, // PROPOSED
  maxOrderQty: 1000000, // rules minOrderQty, kWholesaleMaxOrderQty
  maxUnitWeightG: 10000000, // rules, kMaxUnitWeightG
  maxDimCm: 1000, // rules, kMaxDimCm
  deliveryDaysMax: 365, // PROPOSED
  maxImages: 7, // rules imageUrls ≤ 7, WholesaleProduct.maxImages
  urlMax: 2000,
  batchTtlMs: 24 * 60 * 60 * 1000,
});

const DEFAULT_UNIT = 'дона'; // kWholesaleDefaultUnit
const MARKETS = Object.freeze(['wholesale', 'china']);

/** Хитой валютаси: Excel'даги ёзув → модел қиймати ('' = сўм). */
const CURRENCY_ALIASES = Object.freeze({
  '': '', uzs: '', sum: '', "so'm": '', 'сўм': '', 'сум': '', som: '',
  usd: '$', $: '$', dollar: '$', 'доллар': '$',
  cny: '¥', rmb: '¥', '¥': '¥', yuan: '¥', 'юань': '¥',
});

/** Устунлар: калит, мажбурийми, қайси бозорда, 3 тилдаги сарлавҳа ва ёрдам. */
const IMAGE_KEYS = Object.freeze(Array.from({ length: LIMITS.maxImages }, (_, i) => `image_${i + 1}`));
const COLUMNS = Object.freeze([
  { key: 'sku', required: true, h: ['Артикул (SKU)', 'Artikul (SKU)', 'Артикул (SKU)'],
    help: ['Сизнинг товар кодингиз. Қайта юкласангиз шу код бўйича янгиланади.', 'Sizning tovar kodingiz. Qayta yuklasangiz shu kod bo\'yicha yangilanadi.', 'Ваш код товара. При повторной загрузке товар обновится по этому коду.'] },
  { key: 'title', required: true, h: ['Номи', 'Nomi', 'Название'],
    help: ['3–120 белги', '3–120 belgi', '3–120 символов'] },
  { key: 'description', required: true, h: ['Тавсиф', 'Tavsif', 'Описание'],
    help: ['3–2000 белги', '3–2000 belgi', '3–2000 символов'] },
  { key: 'price', required: true, h: ['Нарх', 'Narx', 'Цена'],
    help: ['Бутун сон, 0 дан катта (1 бирлик нархи)', 'Butun son, 0 dan katta (1 birlik narxi)', 'Целое число больше 0 (цена за 1 единицу)'] },
  { key: 'currency', markets: ['china'], h: ['Валюта', 'Valyuta', 'Валюта'],
    help: ['USD, CNY ёки бўш (сўм)', 'USD, CNY yoki bo\'sh (so\'m)', 'USD, CNY или пусто (сум)'] },
  { key: 'unit', h: ['Бирлик', 'Birlik', 'Единица'],
    help: ['Масалан: дона, кг, қоп. Бўш — дона', 'Masalan: dona, kg, qop. Bo\'sh — dona', 'Например: шт, кг, мешок. Пусто — штука'] },
  { key: 'moq', h: ['Минимал буюртма', 'Minimal buyurtma', 'Минимальный заказ'],
    help: ['Бутун сон 1–1 000 000. Бўш — 1', 'Butun son 1–1 000 000. Bo\'sh — 1', 'Целое 1–1 000 000. Пусто — 1'] },
  { key: 'weight_kg', h: ['Вазн, кг (1 бирлик)', 'Vazn, kg (1 birlik)', 'Вес, кг (1 единица)'],
    help: ['Масалан 1,5. Етказиш ҳақи учун', 'Masalan 1,5. Yetkazish haqi uchun', 'Например 1,5. Для расчёта доставки'] },
  { key: 'length_cm', h: ['Узунлик, см', 'Uzunlik, sm', 'Длина, см'],
    help: ['1–1000, учала ўлчам бирга', '1–1000, uchala o\'lcham birga', '1–1000, все три размера вместе'] },
  { key: 'width_cm', h: ['Эни, см', 'Eni, sm', 'Ширина, см'], help: ['1–1000', '1–1000', '1–1000'] },
  { key: 'height_cm', h: ['Баландлик, см', 'Balandlik, sm', 'Высота, см'], help: ['1–1000', '1–1000', '1–1000'] },
  { key: 'delivery_days', markets: ['china'], h: ['Етказиш, кун', 'Yetkazish, kun', 'Доставка, дней'],
    help: ['1–365, ихтиёрий', '1–365, ixtiyoriy', '1–365, необязательно'] },
  ...IMAGE_KEYS.map((key, i) => ({
    key,
    required: i === 0,
    h: [`Расм ${i + 1} (URL)`, `Rasm ${i + 1} (URL)`, `Фото ${i + 1} (URL)`],
    help: i === 0
      ? ['http(s) ҳавола, камида 1 та расм', 'http(s) havola, kamida 1 ta rasm', 'Ссылка http(s), минимум 1 фото']
      : ['Ихтиёрий', 'Ixtiyoriy', 'Необязательно'],
  })),
]);

function columnsFor(market) {
  return COLUMNS.filter((c) => !c.markets || c.markets.includes(market));
}

/** «Номи* / Nomi* / Название* [title]» */
function headerText(col) {
  const star = col.required ? '*' : '';
  return `${col.h[0]}${star} / ${col.h[1]}${star} / ${col.h[2]}${star} [${col.key}]`;
}

const KEY_SET = new Set(COLUMNS.map((c) => c.key));

/** Сарлавҳа катагидан устун калити: `[key]` белгиси ёки ёлғиз калит; бўлмаса null. */
function keyOfHeader(text) {
  const s = String(text == null ? '' : text).trim();
  const m = s.match(/\[([a-z0-9_]+)\]/i);
  const k = (m ? m[1] : s.replace(/\*/g, '')).trim().toLowerCase();
  return KEY_SET.has(k) ? k : null;
}

/** Каталар: string | number | null (xlsx парсер шундай беради). */
function cellStr(v) {
  if (v == null) return '';
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : '';
  return String(v).replace(/ /g, ' ').trim();
}

/** Бутун сон: рақамли катак ёки «35 000» матни. Ёки { error }. */
function parseIntCell(v) {
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) return { error: 'nan' };
    return Number.isInteger(v) ? { value: v } : { error: 'not_int' };
  }
  const s = cellStr(v).replace(/[\s']/g, '');
  if (s === '') return { empty: true };
  if (/^-?\d+$/.test(s)) return { value: Number(s) };
  if (/^-?\d+[.,]\d+$/.test(s)) return { error: 'not_int' };
  return { error: 'nan' };
}

/** `parseWeightKgToGrams` (shipping_dims.dart) билан бир хил: `1,25`/`1.25` кг → грамм. */
function parseWeightKgToGrams(v) {
  const s = cellStr(v).replace(/\s/g, '').replace(',', '.');
  if (s === '') return null;
  if (!/^\d+(\.\d+)?$/.test(s)) return undefined;
  const kg = Number(s);
  if (!(kg > 0)) return undefined;
  const g = Math.round(kg * 1000);
  return g >= 1 && g <= LIMITS.maxUnitWeightG ? g : undefined;
}

/** SSRF'дан олдинги шакл текшируви (тармоқсиз): фақат http/https, логин-паролсиз, 80/443. */
function imageUrlShapeOk(raw) {
  const s = String(raw || '').trim();
  if (!s || s.length > LIMITS.urlMax) return false;
  let u;
  try { u = new URL(s); } catch (_) { return false; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
  if (u.username || u.password) return false;
  if (u.port && u.port !== '80' && u.port !== '443') return false;
  return !!u.hostname;
}

/** Нусха: клиент `AdSearchText.buildTokens(title, description)` (≤48, асл+лотин+кирилл). */
const CLIENT_MAX_TOKENS = 48;
function clientSearchTokens(title, description) {
  const out = new Set();
  for (const w of words(`${title} ${description}`)) {
    out.add(w);
    const lat = toLatin(w);
    const cyr = toCyrillic(w);
    if (lat.length >= 2) out.add(lat);
    if (cyr.length >= 2) out.add(cyr);
    if (out.size >= CLIENT_MAX_TOKENS) break;
  }
  return Array.from(out).slice(0, CLIENT_MAX_TOKENS);
}

/** SKU таққослаш калити: регистр ва бўшлиқлардан мустақил. */
function normSku(sku) {
  return String(sku || '').trim().replace(/\s+/g, ' ').toUpperCase();
}

/** Детерминистик ҳужжат ID (21-банд): бир сотувчи + бозор + SKU → доим битта маҳсулот. */
function productIdFor(sellerId, market, sku) {
  const h = crypto.createHash('sha256').update(`${sellerId}|${market}|${normSku(sku)}`).digest('hex');
  return `imp_${h.slice(0, 32)}`;
}

/**
 * Расм объекти номи — маҳсулотга ХОС (бир URL икки маҳсулотда бўлса ҳам ўчириш бир-бирига тегмайди):
 * `<productId>_<sha256(url)[0..16]>.jpg`. Бир хил маҳсулот + URL → бир хил йўл (қайта ишлаш идемпотент).
 */
function imageObjectName(productId, url) {
  const h = crypto.createHash('sha256').update(String(url).trim()).digest('hex').slice(0, 16);
  return `${productId}_${h}.jpg`;
}

/** Битта қатор → { fields, imageSources, errors[] } (тармоқсиз текширув). */
function validateRow(cells, market) {
  const errors = [];
  const get = (k) => cells[k];
  const sku = cellStr(get('sku'));
  if (!sku) errors.push('SKU_REQUIRED');
  else if (sku.length > LIMITS.skuMax) errors.push('SKU_TOO_LONG');

  const title = cellStr(get('title')).replace(/\s+/g, ' ');
  if (title.length < LIMITS.titleMin || title.length > LIMITS.titleMax) errors.push('TITLE_INVALID');
  const description = cellStr(get('description'));
  if (description.length < LIMITS.descMin || description.length > LIMITS.descMax) errors.push('DESC_INVALID');

  let price = null;
  const p = parseIntCell(get('price'));
  if (p.empty) errors.push('PRICE_REQUIRED');
  else if (p.error === 'not_int') errors.push('PRICE_NOT_INT');
  else if (p.error || p.value <= 0 || p.value > LIMITS.priceMax) errors.push('PRICE_INVALID');
  else price = p.value;

  let currency = '';
  const curRaw = cellStr(get('currency')).toLowerCase();
  if (curRaw) {
    if (market !== 'china') {
      if (CURRENCY_ALIASES[curRaw] !== '') errors.push('CURRENCY_INVALID');
    } else if (!(curRaw in CURRENCY_ALIASES)) {
      errors.push('CURRENCY_INVALID');
    } else {
      currency = CURRENCY_ALIASES[curRaw];
    }
  }

  let unit = cellStr(get('unit')).replace(/\s+/g, ' ');
  if (unit.length > LIMITS.unitMax) errors.push('UNIT_TOO_LONG');
  if (!unit) unit = DEFAULT_UNIT;

  let minOrderQty = null;
  const m = parseIntCell(get('moq'));
  if (!m.empty) {
    if (m.error || m.value < 1 || m.value > LIMITS.maxOrderQty) errors.push('MOQ_INVALID');
    else minOrderQty = m.value;
  }

  const w = parseWeightKgToGrams(get('weight_kg'));
  if (w === undefined) errors.push('WEIGHT_INVALID');
  const dimRaw = ['length_cm', 'width_cm', 'height_cm'].map((k) => parseIntCell(get(k)));
  const filled = dimRaw.filter((d) => !d.empty).length;
  let unitDims = null;
  if (filled === 3) {
    const ok = dimRaw.every((d) => !d.error && d.value >= 1 && d.value <= LIMITS.maxDimCm);
    if (!ok) errors.push('DIMS_INVALID');
    else unitDims = { l: dimRaw[0].value, w: dimRaw[1].value, h: dimRaw[2].value };
  } else if (filled !== 0) {
    errors.push('DIMS_INVALID');
  }
  if (unitDims && w === null) errors.push('DIMS_NEED_WEIGHT');

  let deliveryDays = null;
  if (market === 'china') {
    const d = parseIntCell(get('delivery_days'));
    if (!d.empty) {
      if (d.error || d.value < 1 || d.value > LIMITS.deliveryDaysMax) errors.push('DELIVERY_DAYS_INVALID');
      else deliveryDays = d.value;
    }
  }

  const imageSources = [];
  let badUrl = false;
  for (const k of IMAGE_KEYS) {
    const u = cellStr(get(k));
    if (!u) continue;
    if (!imageUrlShapeOk(u)) { badUrl = true; continue; }
    if (!imageSources.includes(u)) imageSources.push(u);
  }
  if (badUrl) errors.push('IMAGE_URL_INVALID');
  else if (imageSources.length === 0) errors.push('IMAGE_REQUIRED');

  const fields = {
    title,
    titleLower: title.toLowerCase(),
    description,
    priceTiers: price == null ? [] : [{ minQty: 1, price }],
    unit,
    searchTokens: clientSearchTokens(title, description),
  };
  if (market === 'china') {
    fields.currency = currency;
    if (deliveryDays != null) fields.deliveryDays = deliveryDays;
  }
  if (w != null) fields.unitWeightG = w;
  if (unitDims) fields.unitDims = unitDims;
  if (minOrderQty != null) fields.minOrderQty = minOrderQty;
  return { sku, fields, imageSources, errors };
}

/** Сарлавҳа қатори → { colIndexByKey, error? }. */
function mapHeader(headerCells, market) {
  const idx = {};
  headerCells.forEach((c, i) => {
    const k = keyOfHeader(c);
    if (k && idx[k] === undefined) idx[k] = i;
  });
  const missing = columnsFor(market).filter((c) => c.required && idx[c.key] === undefined).map((c) => c.key);
  return { idx, missing };
}

/**
 * Жадвал (сарлавҳа + қаторлар, Excel қатор рақами билан) → текширилган қаторлар.
 * @param {{ header: any[], rows: { rowNumber: number, cells: any[] }[] }} sheet
 * @returns {{ fileError?: string, missing?: string[], rows: object[] }}
 */
function validateSheet(sheet, market) {
  if (!MARKETS.includes(market)) return { fileError: 'MARKET_INVALID', rows: [] };
  const { idx, missing } = mapHeader(sheet.header || [], market);
  if (missing.length) return { fileError: 'HEADER_MISSING', missing, rows: [] };
  const data = [];
  for (const r of sheet.rows || []) {
    const cells = {};
    for (const [k, i] of Object.entries(idx)) cells[k] = r.cells[i];
    const allEmpty = Object.values(cells).every((v) => cellStr(v) === '');
    if (allEmpty) continue;
    if (cellStr(cells.sku).startsWith('#')) continue; // намуна қатори
    data.push({ rowNumber: r.rowNumber, cells });
  }
  if (data.length === 0) return { fileError: 'NO_ROWS', rows: [] };
  if (data.length > LIMITS.maxRows) return { fileError: 'TOO_MANY_ROWS', rows: [] };

  const rows = data.map((d) => ({ row: d.rowNumber, ...validateRow(d.cells, market) }));
  const bySku = new Map();
  for (const r of rows) {
    if (!r.sku) continue;
    const k = normSku(r.sku);
    bySku.set(k, (bySku.get(k) || 0) + 1);
  }
  for (const r of rows) {
    if (r.sku && bySku.get(normSku(r.sku)) > 1) r.errors.push('SKU_DUPLICATE');
  }
  return { rows };
}

/** Тошкент санаси (UTC+5, ёзги вақтсиз) — кунлик ҳисоблагич калити. */
function tashkentDay(ms) {
  return new Date(ms + 5 * 3600 * 1000).toISOString().slice(0, 10);
}

/** Кунлик квота (тоза): { allowed, next } — next ёзилади. */
function quotaStep(cur, day, max = LIMITS.maxUploadsPerDay) {
  const count = cur && cur.day === day ? Number(cur.count) || 0 : 0;
  if (count >= max) return { allowed: false, next: null, count };
  return { allowed: true, next: { day, count: count + 1 }, count: count + 1 };
}

const CONTENT_KEYS = Object.freeze([
  'title', 'description', 'priceTiers', 'unit', 'currency', 'deliveryDays', 'unitWeightG', 'unitDims', 'minOrderQty',
]);

const canon = (v) => JSON.stringify(v === undefined ? null : v);

/** Мавжуд маҳсулот билан таққослаш: контент ёки расм манбалари ўзгарганми. */
function contentChanged(existing, fields, imageSources) {
  const e = existing || {};
  for (const k of CONTENT_KEYS) {
    let a = e[k];
    let b = fields[k];
    if (k === 'currency') { a = a || ''; b = b || ''; }
    if (k === 'priceTiers') a = Array.isArray(a) ? a.map((t) => ({ minQty: t.minQty, price: t.price })) : a;
    if (k === 'unitDims' && a) a = { l: a.l, w: a.w, h: a.h };
    if (canon(a) !== canon(b)) return true;
  }
  const prevSrc = Array.isArray(e.importImages) ? e.importImages.map((x) => x && x.src) : [];
  return canon(prevSrc) !== canon(imageSources);
}

/**
 * Янгилашдаги ҳолат — эга таҳрири қоидаси билан бир хил (`wholesaleProductOwnerUpdateOk`):
 * контент ўзгарса — қайта модерация (`pending`); сотувчи яширган (`inactive`) бўлса — яширин қолади.
 */
function statusAfterUpdate(existingStatus) {
  return existingStatus === 'inactive' ? 'inactive' : 'pending';
}

module.exports = {
  LIMITS,
  COLUMNS,
  IMAGE_KEYS,
  DEFAULT_UNIT,
  MARKETS,
  CURRENCY_ALIASES,
  CONTENT_KEYS,
  columnsFor,
  headerText,
  keyOfHeader,
  cellStr,
  parseIntCell,
  parseWeightKgToGrams,
  imageUrlShapeOk,
  clientSearchTokens,
  normSku,
  productIdFor,
  imageObjectName,
  validateRow,
  validateSheet,
  mapHeader,
  tashkentDay,
  quotaStep,
  contentChanged,
  statusAfterUpdate,
};
