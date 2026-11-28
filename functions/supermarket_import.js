/**
 * «AVA Супермаркет» — Excel (.xlsx) орқали таклифларни оммавий юклаш (2-босқич, эга 2026-11-21). ФАҚАТ admin/superadmin.
 *
 * Callable'лар:
 *   adminSupermarketImportTemplate({})                                → { fileName, base64 }
 *   adminSupermarketImportPreview({ fileName, fileBase64, clientRequestId })
 *       → { batchId, counts, rows[] } — таклиф ЁЗИЛМАЙДИ
 *   adminSupermarketImportConfirm({ batchId })                        → { status, counts, rows[] }
 *
 * МАВЖУД қисмлар қайта ишлатилади (дубликат йўқ, 4/7-банд):
 *   - .xlsx ўқиш, ZIP-бомба ҳимояси, формула натижаси — `wholesale_import_xlsx.parseXlsx` (сарлавҳада `[sku]` бўлиши шарт);
 *   - катак ўқиш, бутун сон, URL шакли, Тошкент санаси, расм объекти номи — `wholesale_import_rules`;
 *   - расм: SSRF-хавфсиз юклаб олиш + sharp қайта кодлаш — `wholesale_import_images.fetchAndProcess`;
 *   - Storage — `wholesale_import.realFileStore`;
 *   - таклифни ёзиш, таксономия, searchTokens, нарх/харид аудити — `supermarket.js` `upsertOfferTx`
 *     (adminUpsertSupermarketOffer билан АЙНАН бир йўл) + `validateOffer` / `validateCost`.
 *
 * Идемпотентлик: ҳужжат ID = SKU (PRODUCT_ID_RE, adminUpsertSupermarketOffer'даги productId); preview — clientRequestId;
 * confirm — ижара (lease) + ҳар қатор якуний ҳолати (қайта чақирув қолганини давом эттиради); ўзгармаган қатор ёзилмайди.
 * Эски (smGroupId'сиз) platform_products ҳужжатига ёзилмайди — SKU_NOT_SUPERMARKET.
 * Чегара: ≤ 500 қатор (501 — TOO_MANY_ROWS), ≤ 5 МБ.
 * Коллекция: supermarket_imports/{batchId} (client-write ЁПИҚ — rules'да match йўқ); Storage: supermarket_imports/{batchId}.xlsx,
 * расмлар platform_products/sm/<productId>_<hash>.jpg.
 */
'use strict';

const crypto = require('crypto');
const ExcelJS = require('exceljs');
const R = require('./wholesale_import_rules');
const X = require('./wholesale_import_xlsx');
const IMG = require('./wholesale_import_images');
const { realFileStore, pool } = require('./wholesale_import');
const sm = require('./supermarket');

const BATCHES = 'supermarket_imports';
const BATCH_RE = /^smi_[a-f0-9]{24}$/;
const REQ_RE = /^[A-Za-z0-9_-]{8,64}$/;
const LEASE_MS = 9 * 60 * 1000;
const CONFIRM_BUDGET_MS = 470 * 1000;
const ROW_CONCURRENCY = 4;
const TERMINAL = new Set(['created', 'updated', 'unchanged', 'error']);
const IMAGE_PREFIX = 'platform_products/sm/';
const MAX_ROWS = R.LIMITS.maxRows; // 500 — Улгуржи импорти билан бир хил

const L3 = (c, l, r) => [c, l, r];
const UNIT_HELP = Object.freeze(Object.fromEntries(sm.LANGS.map((l) => [l, sm.UNIT_DEFS.map((u) => `${u.id} (${u.labels[l]})`).join(', ')])));
const COLUMNS = Object.freeze([
  { key: 'sku', required: true, h: L3('Артикул (productId)', 'Artikul (productId)', 'Артикул (productId)'), help: L3('6–64 белги: лотин ҳарф, рақам, _ -. Қайта юкласангиз шу артикул янгиланади.', '6–64 belgi: lotin harf, raqam, _ -. Qayta yuklasangiz şu artikul yangilanadi.', '6–64 символа: латиница, цифры, _ -. Повторная загрузка обновит этот артикул.') },
  { key: 'categoryId', h: L3('Бўлим ID', 'Bölim ID', 'ID раздела'), help: L3('Ихтиёрий; берилса гуруҳ бўлимига мос бўлиши шарт', 'Ixtiyoriy; berilsa guruh bölimiga mos bölişi şart', 'Необязательно; если указан — должен совпадать с разделом группы') },
  { key: 'groupId', required: true, h: L3('Гуруҳ ID', 'Guruh ID', 'ID группы'), help: L3('Таксономиядаги гуруҳ, масалан beef, potato', 'Taksonomiyadagi guruh, masalan beef, potato', 'Группа из таксономии, например beef, potato') },
  { key: 'varietyId', h: L3('Нав ID', 'Nav ID', 'ID сорта'), help: L3('Ихтиёрий (a-z, 0-9, _)', 'Ixtiyoriy (a-z, 0-9, _)', 'Необязательно (a-z, 0-9, _)') },
  { key: 'variety_uz_Cyrl', h: L3('Нав (кирилл)', 'Nav (kirill)', 'Сорт (узб. кирилл)'), help: L3('Ихтиёрий, ≤60', 'Ixtiyoriy, ≤60', 'Необязательно, ≤60') },
  { key: 'variety_uz_Latn', h: L3('Нав (лотин)', 'Nav (lotin)', 'Сорт (узб. латиница)'), help: L3('Ихтиёрий, ≤60', 'Ixtiyoriy, ≤60', 'Необязательно, ≤60') },
  { key: 'variety_ru', h: L3('Нав (рус)', 'Nav (rus)', 'Сорт (рус.)'), help: L3('Ихтиёрий, ≤60', 'Ixtiyoriy, ≤60', 'Необязательно, ≤60') },
  { key: 'quality_uz_Cyrl', h: L3('Сифат (кирилл)', 'Sifat (kirill)', 'Качество (узб. кирилл)'), help: L3('Ихтиёрий, ≤30', 'Ixtiyoriy, ≤30', 'Необязательно, ≤30') },
  { key: 'quality_uz_Latn', h: L3('Сифат (лотин)', 'Sifat (lotin)', 'Качество (узб. латиница)'), help: L3('Ихтиёрий, ≤30', 'Ixtiyoriy, ≤30', 'Необязательно, ≤30') },
  { key: 'quality_ru', h: L3('Сифат (рус)', 'Sifat (rus)', 'Качество (рус.)'), help: L3('Ихтиёрий, ≤30', 'Ixtiyoriy, ≤30', 'Необязательно, ≤30') },
  { key: 'packLabel', h: L3('Қадоқ', 'Qadoq', 'Упаковка'), help: L3('Масалан «1 л», ≤40', 'Masalan «1 l», ≤40', 'Например «1 л», ≤40') },
  // Бирликлар рўйхати — supermarket_units.json (ягона манба): «kg (кг)» ёки «кг», «литр», «шт» ҳам қабул қилинади.
  { key: 'unit', h: L3('Бирлик', 'Birlik', 'Единица'), help: L3(`Бўш — гуруҳники. ${UNIT_HELP.uz_Cyrl}`, `Böş — guruhniki. ${UNIT_HELP.uz_Latn}`, `Пусто — из группы. ${UNIT_HELP.ru}`) },
  { key: 'qtyStep', h: L3('Миқдор қадами', 'Miqdor qadami', 'Шаг количества'), help: L3('0,001–1000. Бўш — гуруҳники', '0,001–1000. Böş — guruhniki', '0,001–1000. Пусто — из группы') },
  { key: 'weighed', h: L3('Тортиладими', 'Tortiladimi', 'Весовой'), help: L3('ҳа/йўқ (TRUE/FALSE, 1/0). Бўш — гуруҳники', 'ha/yöq (TRUE/FALSE, 1/0). Böş — guruhniki', 'да/нет (TRUE/FALSE, 1/0). Пусто — из группы') },
  { key: 'packQty', h: L3('Қадоқ миқдори', 'Qadoq miqdori', 'Объём упаковки'), help: L3('Масалан 1,5 (packUnit билан бирга)', 'Masalan 1,5 (packUnit bilan birga)', 'Например 1,5 (вместе с packUnit)') },
  { key: 'packUnit', h: L3('Қадоқ бирлиги', 'Qadoq birligi', 'Единица упаковки'), help: L3('kg, l, piece', 'kg, l, piece', 'kg, l, piece') },
  { key: 'price', required: true, h: L3('Нарх, сўм', 'Narx, söm', 'Цена, сум'), help: L3('Бутун сон > 0 (1 бирлик нархи)', 'Butun son > 0 (1 birlik narxi)', 'Целое число > 0 (цена за единицу)') },
  { key: 'stock', required: true, h: L3('Қолдиқ', 'Qoldiq', 'Остаток'), help: L3('≥ 0, 3 хонагача каср', '≥ 0, 3 xonagaça kasr', '≥ 0, до 3 знаков после запятой') },
  { key: 'status', h: L3('Ҳолат', 'Holat', 'Статус'), help: L3('active, out_of_stock, hidden. Бўш — active', 'active, out_of_stock, hidden. Böş — active', 'active, out_of_stock, hidden. Пусто — active') },
  { key: 'purchasePrice', h: L3('Харид нархи', 'Xarid narxi', 'Закупочная цена'), help: L3('Ихтиёрий, бутун сон ≥ 0 (фақат админ кўради)', 'Ixtiyoriy, butun son ≥ 0 (faqat admin köradi)', 'Необязательно, целое ≥ 0 (видит только админ)') },
  { key: 'supplier', h: L3('Таъминотчи', 'Ta\'minotçi', 'Поставщик'), help: L3('Ихтиёрий, ≤120', 'Ixtiyoriy, ≤120', 'Необязательно, ≤120') },
  { key: 'imageUrl', h: L3('Расм (URL)', 'Rasm (URL)', 'Фото (URL)'), help: L3('Ихтиёрий, очиқ http(s) ҳавола (JPG/PNG/WebP ≤ 10 МБ)', 'Ixtiyoriy, oçiq http(s) havola (JPG/PNG/WebP ≤ 10 MB)', 'Необязательно, открытая ссылка http(s) (JPG/PNG/WebP ≤ 10 МБ)') },
]);
const KEY_BY_LOWER = new Map(COLUMNS.map((c) => [c.key.toLowerCase(), c.key]));

function headerText(c) {
  const star = c.required ? '*' : '';
  return `${c.h[0]}${star} / ${c.h[1]}${star} / ${c.h[2]}${star} [${c.key}]`;
}
function keyOfHeader(text) {
  const s = String(text == null ? '' : text).trim();
  const m = s.match(/\[([A-Za-z0-9_]+)\]/);
  return KEY_BY_LOWER.get((m ? m[1] : s.replace(/\*/g, '')).trim().toLowerCase()) || null;
}

/** Каср сон: рақам ёки «1,5» матни → { value } | { empty } | { error }. */
function parseDecimalCell(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? { value: v } : { error: true };
  const s = R.cellStr(v).replace(/\s/g, '').replace(',', '.');
  if (s === '') return { empty: true };
  return /^-?\d+(\.\d+)?$/.test(s) ? { value: Number(s) } : { error: true };
}
const YES = new Set(['true', '1', 'ha', 'ҳа', 'да', 'yes', 'x', '✔']);
const NO = new Set(['false', '0', "yo'q", 'yöq', 'йўқ', 'нет', 'no']);
function parseBoolCell(v) {
  const s = R.cellStr(v).toLowerCase();
  if (s === '') return { empty: true };
  if (YES.has(s)) return { value: true };
  if (NO.has(s)) return { value: false };
  return { error: true };
}

/** Уч тил: бўш тиллар биринчи тўлдирилгандан олинади; ҳаммаси бўш — null. */
function localized(cells, prefix, max) {
  const raw = sm.LANGS.map((l) => R.cellStr(cells[`${prefix}_${l}`]).replace(/\s+/g, ' '));
  const first = raw.find(Boolean);
  if (!first) return { value: null };
  const value = {};
  sm.LANGS.forEach((l, i) => { value[l] = raw[i] || first; });
  return { value, tooLong: Object.values(value).some((s) => s.length > max) };
}

const DEFAULT_VARIETY = Object.freeze({ id: 'standard', names: { uz_Cyrl: 'Оддий', uz_Latn: 'Oddiy', ru: 'Обычный' } });

/** Битта қатор → { sku, offer, cost, imageSource, errors[] } (тармоқсиз). */
function validateRow(cells) {
  const errors = [];
  const add = (c) => { if (!errors.includes(c)) errors.push(c); };
  const sku = R.cellStr(cells.sku);
  if (!sku) add('SKU_REQUIRED');
  else if (!sm.PRODUCT_ID_RE.test(sku)) add('SKU_INVALID');
  const groupId = R.cellStr(cells.groupId).toLowerCase();
  if (!sm.ID_RE.test(groupId)) add('GROUP_ID_INVALID');
  const categoryId = R.cellStr(cells.categoryId).toLowerCase();
  if (categoryId && !sm.ID_RE.test(categoryId)) add('CATEGORY_ID_INVALID');

  const vNames = localized(cells, 'variety', sm.LIMITS.name);
  if (vNames.tooLong) add('VARIETY_TOO_LONG');
  let varietyId = R.cellStr(cells.varietyId).toLowerCase();
  if (varietyId && !sm.ID_RE.test(varietyId)) add('VARIETY_ID_INVALID');
  let variety;
  if (!vNames.value) {
    variety = varietyId ? { id: varietyId, names: { ...DEFAULT_VARIETY.names } } : { ...DEFAULT_VARIETY, names: { ...DEFAULT_VARIETY.names } };
  } else {
    if (!varietyId) {
      const norm = sm.LANGS.map((l) => vNames.value[l].toLowerCase()).join('|');
      varietyId = `v${crypto.createHash('sha256').update(norm).digest('hex').slice(0, 12)}`;
    }
    variety = { id: varietyId, names: vNames.value };
  }
  const quality = localized(cells, 'quality', 30);
  if (quality.tooLong) add('QUALITY_TOO_LONG');

  const offer = { smGroupId: groupId, smVariety: variety };
  if (quality.value) offer.smQuality = quality.value;
  const packLabel = R.cellStr(cells.packLabel).replace(/\s+/g, ' ');
  if (packLabel) offer.packLabel = packLabel;
  const unit = sm.unitFromInput(R.cellStr(cells.unit));
  if (unit === null) add('UNIT_INVALID');
  else if (unit) offer.unit = unit;
  const step = parseDecimalCell(cells.qtyStep);
  if (step.error || (!step.empty && !sm.stepOk(step.value))) add('STEP_INVALID');
  else if (!step.empty) offer.qtyStep = step.value;
  const w = parseBoolCell(cells.weighed);
  if (w.error) add('WEIGHED_INVALID');
  else if (!w.empty) offer.weighed = w.value;
  const pq = parseDecimalCell(cells.packQty);
  const puRaw = R.cellStr(cells.packUnit);
  const pu = sm.unitFromInput(puRaw) || puRaw.toLowerCase(); // номаълум — validateOffer PACK_UNIT_INVALID
  if (pq.error) add('PACK_QTY_INVALID');
  else if (!pq.empty || pu) {
    offer.packQty = pq.empty ? null : pq.value;
    offer.packUnit = pu || null;
  }
  const price = R.parseIntCell(cells.price);
  if (price.empty) add('PRICE_REQUIRED');
  else if (price.error === 'not_int') add('PRICE_NOT_INT');
  else if (price.error) add('PRICE_INVALID');
  else offer.price = price.value;
  const stock = parseDecimalCell(cells.stock);
  if (stock.empty) add('STOCK_REQUIRED');
  else if (stock.error) add('STOCK_INVALID');
  else offer.stock = stock.value;
  const status = R.cellStr(cells.status).toLowerCase() || 'active';
  offer.smStatus = status;

  let cost = null;
  const pp = R.parseIntCell(cells.purchasePrice);
  const supplier = R.cellStr(cells.supplier);
  if (pp.error) add('PURCHASE_PRICE_INVALID');
  else if (!pp.empty) cost = { purchasePrice: pp.value, supplier };
  else if (supplier) add('PURCHASE_PRICE_REQUIRED');

  const imageSource = R.cellStr(cells.imageUrl);
  if (imageSource && !R.imageUrlShapeOk(imageSource)) add('IMAGE_URL_INVALID');

  // Якуний текширув — callable билан бир хил валидатор (ягона манба).
  if (!errors.length) {
    const v = sm.validateOffer(offer);
    for (const e of v.errors) add(String(e).split(' ')[0]);
    if (cost) for (const e of sm.validateCost(cost).errors) add(String(e).split(' ')[0]);
  }
  return { sku, categoryId, offer, cost, imageSource, errors };
}

/**
 * Жадвал → текширилган қаторлар. taxonomy — гуруҳ/бўлим мавжудлиги (GROUP_UNKNOWN / CATEGORY_MISMATCH).
 * @returns {{ fileError?: string, missing?: string[], rows: object[] }}
 */
function validateSheet(sheet, taxonomy) {
  const idx = {};
  (sheet.header || []).forEach((h, i) => {
    const k = keyOfHeader(h);
    if (k && idx[k] === undefined) idx[k] = i;
  });
  const missing = COLUMNS.filter((c) => c.required && idx[c.key] === undefined).map((c) => c.key);
  if (missing.length) return { fileError: 'HEADER_MISSING', missing, rows: [] };
  const data = [];
  for (const r of sheet.rows || []) {
    const cells = {};
    for (const [k, i] of Object.entries(idx)) cells[k] = r.cells[i];
    if (Object.values(cells).every((v) => R.cellStr(v) === '')) continue;
    if (R.cellStr(cells.sku).startsWith('#')) continue; // намуна
    data.push({ rowNumber: r.rowNumber, cells });
  }
  if (data.length === 0) return { fileError: 'NO_ROWS', rows: [] };
  if (data.length > MAX_ROWS) return { fileError: 'TOO_MANY_ROWS', rows: [] };
  const rows = data.map((d) => ({ row: d.rowNumber, ...validateRow(d.cells) }));
  const count = new Map();
  for (const r of rows) if (r.sku) count.set(r.sku, (count.get(r.sku) || 0) + 1);
  for (const r of rows) {
    if (r.sku && count.get(r.sku) > 1) r.errors.push('SKU_DUPLICATE');
    if (r.errors.includes('GROUP_ID_INVALID')) continue;
    const found = sm.findGroup(taxonomy, r.offer.smGroupId);
    if (!found) r.errors.push('GROUP_UNKNOWN');
    else if (r.categoryId && found.category.id !== r.categoryId) r.errors.push('CATEGORY_MISMATCH');
  }
  return { rows };
}

async function buildTemplate() {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'AVA';
  const ws = wb.addWorksheet(X.SHEET_PRODUCTS, { views: [{ state: 'frozen', ySplit: 1 }] });
  ws.columns = COLUMNS.map((c) => ({ header: headerText(c), key: c.key, width: 22 }));
  const head = ws.getRow(1);
  head.font = { bold: true };
  head.alignment = { wrapText: true, vertical: 'top' };
  head.height = 48;
  const sample = ws.addRow({
    sku: '#beef_lean_1', categoryId: 'meat_fish', groupId: 'beef', varietyId: 'lean',
    variety_uz_Cyrl: 'Лаҳм', variety_uz_Latn: 'Lahm', variety_ru: 'Постная', quality_uz_Cyrl: 'Олий', quality_uz_Latn: 'Oliy', quality_ru: 'Высший',
    unit: 'kg', qtyStep: 0.5, weighed: 'TRUE', price: 80000, stock: 10, status: 'active', purchasePrice: 70000, supplier: 'Гурлан бозори',
    imageUrl: 'https://example.com/beef.jpg',
  });
  sample.font = { italic: true, color: { argb: 'FF888888' } };
  ws.getColumn('sku').numFmt = '@';
  ws.getColumn('price').numFmt = '0';
  const help = wb.addWorksheet(X.SHEET_HELP);
  help.columns = [
    { header: 'Устун / Ustun / Колонка', key: 'col', width: 34 },
    { header: 'Мажбурий / Majburiy / Обязательно', key: 'req', width: 14 },
    { header: 'Ўзбекча (кирилл)', key: 'cyr', width: 50 },
    { header: 'Özbekça (lotin)', key: 'lat', width: 50 },
    { header: 'Русский', key: 'ru', width: 50 },
  ];
  help.getRow(1).font = { bold: true };
  for (const c of COLUMNS) help.addRow({ col: headerText(c), req: c.required ? '✔' : '', cyr: c.help[0], lat: c.help[1], ru: c.help[2] });
  help.addRow({});
  for (const n of [
    ['«#» билан бошланган артикул — намуна, юкланмайди.', '«#» bilan boşlangan artikul — namuna, yuklanmaydi.', 'Артикул, начинающийся с «#», — образец, не загружается.'],
    [`Бир файлда ≤ ${MAX_ROWS} қатор, ≤ 5 МБ.`, `Bir faylda ≤ ${MAX_ROWS} qator, ≤ 5 MB.`, `В файле ≤ ${MAX_ROWS} строк, ≤ 5 МБ.`],
    ['Нарх ўзгариши аудитга ёзилади. Ўзгармаган қатор ёзилмайди.', 'Narx özgarişi auditga yoziladi. Özgarmagan qator yozilmaydi.', 'Изменение цены пишется в аудит. Неизменённые строки не записываются.'],
  ]) help.addRow({ col: '', req: '', cyr: n[0], lat: n[1], ru: n[2] });
  return Buffer.from(await wb.xlsx.writeBuffer());
}

function attachSupermarketImport(exportsObj, deps) {
  const { functions, db, admin, smApi } = deps;
  const HttpsError = functions.https.HttpsError;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const log = (o) => console.log(JSON.stringify({ module: 'supermarket_import', ...o }));
  const store = deps.fileStore || realFileStore(admin);
  const processImage = deps.processImage || ((url) => IMG.fetchAndProcess(url));
  const now = deps.now || (() => Date.now());
  const requireAdmin = smApi.requireAdmin;

  function decodeFile(b64) {
    const s = typeof b64 === 'string' ? b64 : '';
    if (!s) throw fail('invalid-argument', 'FILE_EMPTY');
    if (s.length > Math.ceil((R.LIMITS.maxFileBytes * 4) / 3) + 8) throw fail('invalid-argument', 'FILE_TOO_LARGE');
    const buf = Buffer.from(s, 'base64');
    if (buf.length === 0) throw fail('invalid-argument', 'FILE_EMPTY');
    if (buf.length > R.LIMITS.maxFileBytes) throw fail('invalid-argument', 'FILE_TOO_LARGE');
    return buf;
  }

  /** partner — {id, key} (эга 2026-11-28: ҳамкор импорти) ёки null (админ). Ҳамкор SKU'си ps_{калит}_{sku} га, харид нархи эътиборсиз. */
  async function analyse(buf, partner = null) {
    const parsed = await X.parseXlsx(buf);
    if (!parsed.ok) return { fileError: parsed.code, rows: [] };
    const taxSnap = await db.collection(sm.TAXONOMY_DOC[0]).doc(sm.TAXONOMY_DOC[1]).get();
    if (!taxSnap.exists) return { fileError: 'TAXONOMY_MISSING', rows: [] };
    const v = validateSheet(parsed.sheet, taxSnap.data() || {});
    if (v.fileError) return v;
    for (const r of v.rows) {
      r.productId = r.sku;
      if (partner) {
        r.cost = null;
        r.productId = sm.partnerProductId(partner.id, r.sku);
        if (!r.productId && !r.errors.includes('SKU_INVALID')) r.errors.push('SKU_INVALID');
      }
    }
    const withSku = v.rows.filter((r) => r.productId && sm.PRODUCT_ID_RE.test(r.productId) && !r.errors.includes('SKU_DUPLICATE'));
    const snaps = withSku.length ? await db.getAll(...withSku.map((r) => db.collection('platform_products').doc(r.productId))) : [];
    const existing = new Map();
    snaps.forEach((s, i) => existing.set(withSku[i].row, s.exists ? (s.data() || {}) : null));
    for (const r of v.rows) {
      const e = existing.get(r.row);
      if (e && !e.smGroupId) r.errors.push('SKU_NOT_SUPERMARKET');
      if (partner && e && (e.smPartnerKey !== partner.key || e.smSample === true)) r.errors.push('SKU_NOT_OWNED');
      r.action = e ? 'update' : 'create';
    }
    return { rows: v.rows };
  }

  const countsOf = (rows) => {
    const ok = rows.filter((r) => r.errors.length === 0);
    return {
      total: rows.length, ready: ok.length, errors: rows.length - ok.length,
      create: ok.filter((r) => r.action === 'create').length, update: ok.filter((r) => r.action === 'update').length,
    };
  };
  const compactRow = (r) => ({ row: r.row, sku: r.sku, groupId: r.offer.smGroupId, price: r.offer.price == null ? null : r.offer.price, action: r.errors.length ? 'error' : r.action, errors: r.errors });

  exportsObj.adminSupermarketImportTemplate = functions.https.onCall(async (data, context) => {
    await requireAdmin(context);
    return { fileName: 'ava_supermarket_offers.xlsx', base64: (await buildTemplate()).toString('base64') };
  });

  exportsObj.adminSupermarketImportPreview = functions.runWith({ timeoutSeconds: 120, memory: '1GB' }).https.onCall(async (data, context) =>
    previewFor(await requireAdmin(context), null, data));

  /** Ҳамкор (тасдиқланган Улгуржи сотувчиси) — ўз таклифлари учун ўша импорт (эга 2026-11-28). */
  exportsObj.partnerSupermarketImportTemplate = functions.https.onCall(async (data, context) => {
    await smApi.requirePartner(context);
    return { fileName: 'ava_supermarket_partner.xlsx', base64: (await buildTemplate()).toString('base64') };
  });
  exportsObj.partnerSupermarketImportPreview = functions.runWith({ timeoutSeconds: 120, memory: '1GB' }).https.onCall(async (data, context) => {
    const partner = await smApi.requirePartner(context);
    return previewFor(partner.id, partner, data);
  });
  exportsObj.partnerSupermarketImportConfirm = functions.runWith({ timeoutSeconds: 540, memory: '1GB' }).https.onCall(async (data, context) => {
    const partner = await smApi.requirePartner(context);
    return confirmFor(partner.id, partner, data);
  });

  async function previewFor(actor, partner, data) {
    const started = now();
    const d = data || {};
    const clientRequestId = String(d.clientRequestId || '').trim();
    if (!REQ_RE.test(clientRequestId)) throw fail('invalid-argument', 'REQUEST_ID_INVALID');
    const batchId = `smi_${crypto.createHash('sha256').update(`${actor}|${clientRequestId}`).digest('hex').slice(0, 24)}`;
    const batchRef = db.collection(BATCHES).doc(batchId);
    const prev = await batchRef.get();
    if (prev.exists && prev.data().preview) return { batchId, duplicate: true, ...prev.data().preview };

    const buf = decodeFile(d.fileBase64);
    const fileName = String(d.fileName || 'import.xlsx').slice(0, 120);
    const fileSha256 = crypto.createHash('sha256').update(buf).digest('hex');
    const a = await analyse(buf, partner);
    if (a.fileError) {
      await batchRef.set({ actor, ...(partner ? { partnerKey: partner.key } : {}), fileName, fileSha256, fileBytes: buf.length, clientRequestId, status: 'rejected', fileError: a.fileError, missing: a.missing || [], createdAt: ts() });
      log({ action: 'preview', userId: actor, batchId, result: a.fileError, duration: now() - started });
      throw fail('invalid-argument', a.fileError, { missing: a.missing || [] });
    }
    const storagePath = `${BATCHES}/${batchId}.xlsx`;
    await store.saveFile(storagePath, buf, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    const preview = { counts: countsOf(a.rows), rows: a.rows.map(compactRow) };
    await batchRef.set({ actor, ...(partner ? { partnerKey: partner.key } : {}), fileName, fileSha256, fileBytes: buf.length, storagePath, clientRequestId, status: 'previewed', preview, createdAt: ts(), createdAtMs: now() });
    log({ action: 'preview', userId: partner ? partner.key : actor, batchId, result: 'ok', counts: preview.counts, duration: now() - started });
    return { batchId, duplicate: false, ...preview };
  }

  /** Битта қатор: расм (керак бўлса) → upsertOfferTx (ягона ёзиш йўли). */
  async function writeRow(r, ctx) {
    const pid = r.productId || r.sku;
    const ref = db.collection('platform_products').doc(pid);
    const pre = await ref.get();
    const cur = pre.exists ? (pre.data() || {}) : null;
    if (cur && !cur.smGroupId) return { status: 'error', codes: ['SKU_NOT_SUPERMARKET'] };
    const offer = { ...r.offer };
    let imageSrc = cur && typeof cur.smImageSrc === 'string' ? cur.smImageSrc : '';
    let newUrl = null;
    if (r.imageSource) {
      if (cur && cur.smImageSrc === r.imageSource && cur.imageUrl) {
        offer.imageUrl = cur.imageUrl;
      } else {
        try {
          const jpeg = await processImage(r.imageSource);
          newUrl = await store.saveImage(`${IMAGE_PREFIX}${R.imageObjectName(pid, r.imageSource)}`, jpeg);
        } catch (e) {
          return { status: 'error', codes: [e && e.code && /^IMAGE_/.test(e.code) ? e.code : 'IMAGE_FETCH_FAILED'] };
        }
        offer.imageUrl = newUrl;
      }
      imageSrc = r.imageSource;
    }
    let res;
    try {
      res = await db.runTransaction((t) => smApi.upsertOfferTx(t, {
        productId: pid, offer, cost: ctx.partner ? null : r.cost, actor: ctx.actor, imp: { batchId: ctx.batchId, imageSrc },
        partner: ctx.partner || undefined, autoApprove: ctx.autoApprove,
      }));
    } catch (e) {
      return { status: 'error', codes: [(e && e.details && e.details.code) || 'WRITE_FAILED'] };
    }
    if (newUrl && cur && cur.imageUrl && cur.imageUrl !== newUrl) {
      try { await store.deleteByUrl(cur.imageUrl, `${IMAGE_PREFIX}${pid}_`); } catch (_) { /* best-effort */ }
    }
    return { status: res.unchanged ? 'unchanged' : (res.created ? 'created' : 'updated'), priceChanged: res.priceChanged };
  }

  exportsObj.adminSupermarketImportConfirm = functions.runWith({ timeoutSeconds: 540, memory: '1GB' }).https.onCall(async (data, context) =>
    confirmFor(await requireAdmin(context), null, data));

  async function confirmFor(actor, partner, data) {
    const started = now();
    const batchId = String((data || {}).batchId || '');
    if (!BATCH_RE.test(batchId)) throw fail('invalid-argument', 'BATCH_NOT_FOUND');
    const batchRef = db.collection(BATCHES).doc(batchId);
    const claim = await db.runTransaction(async (t) => {
      const s = await t.get(batchRef);
      if (!s.exists) throw fail('not-found', 'BATCH_NOT_FOUND');
      const b = s.data() || {};
      // Ҳамкор — фақат ЎЗ партияси; админ — ҳамкор партиясини тасдиқламайди (ёзув эгаси аралашмасин).
      if ((b.partnerKey || null) !== (partner ? partner.key : null)) throw fail('not-found', 'BATCH_NOT_FOUND');
      if (b.status === 'done') return { done: true, b };
      if (!['previewed', 'partial', 'processing'].includes(b.status)) throw fail('failed-precondition', 'BATCH_NOT_FOUND');
      if (b.status === 'previewed' && now() - Number(b.createdAtMs || 0) > R.LIMITS.batchTtlMs) throw fail('failed-precondition', 'BATCH_EXPIRED');
      if (b.status === 'processing' && Number(b.leaseUntilMs || 0) > now()) throw fail('aborted', 'BATCH_BUSY');
      t.update(batchRef, { status: 'processing', leaseUntilMs: now() + LEASE_MS, confirmStartedAt: ts(), confirmedBy: actor });
      return { done: false, b };
    });
    if (claim.done) return { batchId, status: 'done', duplicate: true, ...claim.b.result };
    const b = claim.b;
    let rows;
    try {
      const buf = await store.readFile(b.storagePath);
      if (crypto.createHash('sha256').update(buf).digest('hex') !== b.fileSha256) throw fail('failed-precondition', 'FILE_CHANGED');
      const a = await analyse(buf, partner);
      if (a.fileError) throw fail('invalid-argument', a.fileError);
      rows = a.rows;
    } catch (e) {
      await batchRef.update({ status: 'previewed', leaseUntilMs: 0 });
      throw e instanceof HttpsError ? e : fail('internal', 'IMPORT_READ_FAILED');
    }
    const rowStatus = { ...(b.rowStatus || {}) };
    for (const r of rows) if (r.errors.length) rowStatus[r.row] = { status: 'error', codes: r.errors };
    const todo = rows.filter((r) => !r.errors.length && !(rowStatus[r.row] && TERMINAL.has(rowStatus[r.row].status)));
    const deadline = started + CONFIRM_BUDGET_MS;
    const ctx = { batchId, actor, partner, autoApprove: partner ? await smApi.partnerAutoApprove() : undefined };
    await pool(todo, ROW_CONCURRENCY, async (r) => {
      if (now() > deadline) return;
      try {
        const res = await writeRow(r, ctx);
        rowStatus[r.row] = res.codes ? { status: res.status, codes: res.codes } : { status: res.status };
      } catch (e) {
        log({ action: 'confirm_row', batchId, row: r.row, result: 'WRITE_FAILED' });
        rowStatus[r.row] = { status: 'error', codes: ['WRITE_FAILED'] };
      }
    });
    const outRows = rows.map((r) => {
      const st = rowStatus[r.row] || { status: 'pending' };
      return { row: r.row, sku: r.sku, status: st.status, errors: st.codes || [] };
    });
    const counts = { total: outRows.length };
    for (const k of ['created', 'updated', 'unchanged', 'error', 'pending']) counts[k] = outRows.filter((x) => x.status === k).length;
    const status = counts.pending > 0 ? 'partial' : 'done';
    const result = { counts, rows: outRows };
    await batchRef.update({ status, rowStatus, result, leaseUntilMs: 0, lastConfirmAt: ts(), ...(status === 'done' ? { finishedAt: ts() } : {}) });
    if (status === 'done') {
      await db.collection('admin_audit').doc(`supermarket_import_${batchId}`).set({
        kind: 'supermarket_import', actor, target: `${BATCHES}/${batchId}`, counts, fileSha256: b.fileSha256, at: ts(),
      });
    }
    log({ action: 'confirm', batchId, userId: partner ? partner.key : actor, result: status, counts, duration: now() - started });
    return { batchId, status, duplicate: false, ...result };
  }
}

module.exports = {
  attachSupermarketImport, COLUMNS, MAX_ROWS, headerText, keyOfHeader, validateRow, validateSheet, buildTemplate, parseDecimalCell, parseBoolCell,
};
