/**
 * Улгуржи/Хитой Excel юклаш — .xlsx ўқиш ва шаблон ясаш (exceljs, MIT).
 *
 * Хавфсизлик: файл ≤ 5 МБ (чақирувчи текширади), ZIP «бомба»га қарши — exceljs'га беришдан
 * ОЛДИН марказий каталогдаги очилган ҳажмлар йиғиндиси ≤ LIMITS.maxUncompressedBytes; Zip64 рад.
 * Формула ҳисобланмайди — фақат Excel сақлаган натижа (`result`) олинади.
 */
'use strict';

const ExcelJS = require('exceljs');
const R = require('./wholesale_import_rules');

const SHEET_PRODUCTS = 'Products';
const SHEET_HELP = 'Help';

/** ZIP марказий каталогини ўқийди → { ok, entries, uncompressed } ёки { ok:false, code }. */
function inspectZip(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 22) return { ok: false, code: 'FILE_NOT_XLSX' };
  if (buf.readUInt32LE(0) !== 0x04034b50) return { ok: false, code: 'FILE_NOT_XLSX' };
  const from = Math.max(0, buf.length - 22 - 0xffff);
  let eocd = -1;
  for (let i = buf.length - 22; i >= from; i -= 1) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) return { ok: false, code: 'FILE_NOT_XLSX' };
  const entries = buf.readUInt16LE(eocd + 10);
  const cdSize = buf.readUInt32LE(eocd + 12);
  const cdOffset = buf.readUInt32LE(eocd + 16);
  if (entries === 0xffff || cdOffset === 0xffffffff || cdOffset + cdSize > buf.length) {
    return { ok: false, code: 'FILE_NOT_XLSX' };
  }
  let p = cdOffset;
  let total = 0;
  for (let n = 0; n < entries; n += 1) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) return { ok: false, code: 'FILE_NOT_XLSX' };
    const size = buf.readUInt32LE(p + 24);
    if (size === 0xffffffff) return { ok: false, code: 'FILE_TOO_LARGE' };
    total += size;
    if (total > R.LIMITS.maxUncompressedBytes) return { ok: false, code: 'FILE_TOO_LARGE' };
    p += 46 + buf.readUInt16LE(p + 28) + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32);
  }
  return { ok: true, entries, uncompressed: total };
}

/** exceljs катак қиймати → string | number | null. */
function plainValue(v) {
  if (v == null) return null;
  if (typeof v === 'number' || typeof v === 'string') return v;
  if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE';
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if (typeof v === 'object') {
    if (Array.isArray(v.richText)) return v.richText.map((t) => (t && t.text) || '').join('');
    if ('result' in v) return plainValue(v.result);
    if (v.hyperlink && typeof v.text !== 'object') return v.text != null ? String(v.text) : String(v.hyperlink);
    if (typeof v.text === 'string') return v.text;
    if (v.text && Array.isArray(v.text.richText)) return v.text.richText.map((t) => (t && t.text) || '').join('');
    if (v.error) return null;
  }
  return null;
}

/**
 * .xlsx → { header, rows:[{rowNumber, cells}] } (биринчи сарлавҳали варақ).
 * @returns {Promise<{ ok: true, sheet } | { ok: false, code }>}
 */
async function parseXlsx(buf) {
  if (!Buffer.isBuffer(buf) || buf.length === 0) return { ok: false, code: 'FILE_EMPTY' };
  if (buf.length > R.LIMITS.maxFileBytes) return { ok: false, code: 'FILE_TOO_LARGE' };
  const z = inspectZip(buf);
  if (!z.ok) return z;
  const wb = new ExcelJS.Workbook();
  try {
    await wb.xlsx.load(buf);
  } catch (_) {
    return { ok: false, code: 'FILE_NOT_XLSX' };
  }
  const sheets = [];
  const named = wb.getWorksheet(SHEET_PRODUCTS);
  if (named) sheets.push(named);
  wb.eachSheet((ws) => { if (ws !== named) sheets.push(ws); });
  for (const ws of sheets) {
    const headerRow = ws.getRow(1);
    const header = [];
    const width = Math.min(ws.columnCount || 0, 64);
    for (let c = 1; c <= width; c += 1) header.push(plainValue(headerRow.getCell(c).value));
    if (!header.some((h) => R.keyOfHeader(h) === 'sku')) continue;
    const rows = [];
    const last = ws.rowCount || 0;
    // Чегарадан ошиқ қаторни ўқиб ўтирмаймиз: maxRows + бўш/намуна қаторлари учун захира.
    const hardCap = R.LIMITS.maxRows * 3 + 50;
    for (let r = 2; r <= last && rows.length <= hardCap; r += 1) {
      const row = ws.getRow(r);
      const cells = [];
      for (let c = 1; c <= width; c += 1) cells.push(plainValue(row.getCell(c).value));
      if (cells.every((v) => v == null || String(v).trim() === '')) continue;
      rows.push({ rowNumber: r, cells });
    }
    return { ok: true, sheet: { header, rows } };
  }
  return { ok: false, code: 'HEADER_MISSING' };
}

/** Шаблон: «Products» (3 тилли сарлавҳа + намуна қатори «#…») ва «Help» (устунлар изоҳи). */
async function buildTemplate(market) {
  const cols = R.columnsFor(market);
  const wb = new ExcelJS.Workbook();
  wb.creator = 'AVA';
  const ws = wb.addWorksheet(SHEET_PRODUCTS, { views: [{ state: 'frozen', ySplit: 1 }] });
  ws.columns = cols.map((c) => ({ header: R.headerText(c), key: c.key, width: c.key === 'description' ? 40 : 22 }));
  const head = ws.getRow(1);
  head.font = { bold: true };
  head.alignment = { wrapText: true, vertical: 'top' };
  head.height = 48;
  const sample = {
    sku: '#NAMUNA-1',
    title: 'Ун, олий нав, 50 кг',
    description: 'Олий навли буғдой уни. Қоп 50 кг.',
    price: market === 'china' ? 25 : 350000,
    currency: market === 'china' ? 'USD' : undefined,
    unit: 'қоп',
    moq: 10,
    weight_kg: 50,
    length_cm: 80,
    width_cm: 50,
    height_cm: 15,
    delivery_days: market === 'china' ? 20 : undefined,
    image_1: 'https://example.com/un.jpg',
  };
  const sampleRow = ws.addRow(sample);
  sampleRow.font = { italic: true, color: { argb: 'FF888888' } };
  for (const c of cols) {
    if (c.key === 'price' || c.key === 'moq' || c.key.endsWith('_cm') || c.key === 'delivery_days') {
      ws.getColumn(c.key).numFmt = '0';
    }
    if (c.key === 'sku') ws.getColumn(c.key).numFmt = '@';
  }

  const help = wb.addWorksheet(SHEET_HELP);
  help.columns = [
    { header: 'Устун / Ustun / Колонка', key: 'col', width: 34 },
    { header: 'Мажбурий / Majburiy / Обязательно', key: 'req', width: 14 },
    { header: 'Ўзбекча (кирилл)', key: 'cyr', width: 50 },
    { header: "O'zbekcha (lotin)", key: 'lat', width: 50 },
    { header: 'Русский', key: 'ru', width: 50 },
  ];
  help.getRow(1).font = { bold: true };
  for (const c of cols) {
    help.addRow({ col: R.headerText(c), req: c.required ? '✔' : '', cyr: c.help[0], lat: c.help[1], ru: c.help[2] });
  }
  help.addRow({});
  const notes = [
    ['«#» билан бошланган артикул — намуна, юкланмайди.', "«#» bilan boshlangan artikul — namuna, yuklanmaydi.", 'Артикул, начинающийся с «#», — образец, не загружается.'],
    [`Бир файлда ≤ ${R.LIMITS.maxRows} қатор, ≤ 5 МБ; кунига ≤ ${R.LIMITS.maxUploadsPerDay} марта.`, `Bir faylda ≤ ${R.LIMITS.maxRows} qator, ≤ 5 MB; kuniga ≤ ${R.LIMITS.maxUploadsPerDay} marta.`, `В файле ≤ ${R.LIMITS.maxRows} строк, ≤ 5 МБ; ≤ ${R.LIMITS.maxUploadsPerDay} загрузок в день.`],
    ['Шу артикул билан қайта юкласангиз — товар янгиланади ва қайта текширувга тушади.', "Shu artikul bilan qayta yuklasangiz — tovar yangilanadi va qayta tekshiruvga tushadi.", 'Повторная загрузка с тем же артикулом обновит товар и отправит его на повторную проверку.'],
    ['Расм ҳаволаси очиқ бўлсин (JPG/PNG/WebP, ≤ 10 МБ).', "Rasm havolasi ochiq bo'lsin (JPG/PNG/WebP, ≤ 10 MB).", 'Ссылка на фото должна быть открытой (JPG/PNG/WebP, ≤ 10 МБ).'],
  ];
  for (const n of notes) help.addRow({ col: '', req: '', cyr: n[0], lat: n[1], ru: n[2] });
  help.getColumn('cyr').alignment = { wrapText: true };
  help.getColumn('lat').alignment = { wrapText: true };
  help.getColumn('ru').alignment = { wrapText: true };
  return Buffer.from(await wb.xlsx.writeBuffer());
}

module.exports = { inspectZip, plainValue, parseXlsx, buildTemplate, SHEET_PRODUCTS, SHEET_HELP };
