/**
 * Улгуржи Excel юклаш — соф қоидалар, xlsx парсер/шаблон, SSRF ҳимояси, расм қайта кодлаш.
 *   node test/wholesale_import_rules.test.js
 */
'use strict';
const assert = require('assert');
const http = require('http');
const R = require('../wholesale_import_rules');
const X = require('../wholesale_import_xlsx');
const IMG = require('../wholesale_import_images');
const ExcelJS = require('exceljs');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

const okCells = (over = {}) => ({
  sku: 'A-1', title: 'Ун олий нав', description: 'Яхши ун', price: 350000, unit: 'қоп', moq: 10,
  weight_kg: '1,5', length_cm: 80, width_cm: 50, height_cm: 15, image_1: 'https://example.com/a.jpg', ...over,
});
const codes = (cells, market = 'wholesale') => R.validateRow(cells, market).errors;
const header = (market) => R.columnsFor(market).map(R.headerText);
const sheetOf = (market, rowsCells) => {
  const cols = R.columnsFor(market).map((c) => c.key);
  return { header: header(market), rows: rowsCells.map((c, i) => ({ rowNumber: i + 2, cells: cols.map((k) => c[k]) })) };
};

async function xlsxOf(headerRow, dataRows) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Products');
  ws.addRow(headerRow);
  for (const r of dataRows) ws.addRow(r);
  return Buffer.from(await wb.xlsx.writeBuffer());
}

async function main() {
  await check('R1 to\'g\'ri qator: maydonlar, bitta narx pog\'onasi, gramm, o\'lcham', () => {
    const v = R.validateRow(okCells(), 'wholesale');
    assert.deepStrictEqual(v.errors, []);
    assert.deepStrictEqual(v.fields.priceTiers, [{ minQty: 1, price: 350000 }]);
    assert.strictEqual(v.fields.minOrderQty, 10);
    assert.strictEqual(v.fields.unitWeightG, 1500);
    assert.deepStrictEqual(v.fields.unitDims, { l: 80, w: 50, h: 15 });
    assert.strictEqual(v.fields.unit, 'қоп');
    assert.ok(!('currency' in v.fields));
    assert.ok(v.fields.searchTokens.includes('ун') && v.fields.searchTokens.includes('un'));
  });

  await check('R2 narx: 0/manfiy/kasr/matn/bo\'sh/katta — xato; "35 000" matni — to\'g\'ri', () => {
    assert.deepStrictEqual(codes(okCells({ price: 0 })), ['PRICE_INVALID']);
    assert.deepStrictEqual(codes(okCells({ price: -5 })), ['PRICE_INVALID']);
    assert.deepStrictEqual(codes(okCells({ price: 1000.5 })), ['PRICE_NOT_INT']);
    assert.deepStrictEqual(codes(okCells({ price: '1000,5' })), ['PRICE_NOT_INT']);
    assert.deepStrictEqual(codes(okCells({ price: 'abc' })), ['PRICE_INVALID']);
    assert.deepStrictEqual(codes(okCells({ price: '' })), ['PRICE_REQUIRED']);
    assert.deepStrictEqual(codes(okCells({ price: R.LIMITS.priceMax + 1 })), ['PRICE_INVALID']);
    assert.deepStrictEqual(codes(okCells({ price: R.LIMITS.priceMax })), []);
    assert.strictEqual(R.validateRow(okCells({ price: '35 000' }), 'wholesale').fields.priceTiers[0].price, 35000);
    assert.deepStrictEqual(codes(okCells({ price: 1 })), []);
  });

  await check('R3 nom/tavsif chegaralari (rules 3..120, 3..2000)', () => {
    assert.deepStrictEqual(codes(okCells({ title: 'ab' })), ['TITLE_INVALID']);
    assert.deepStrictEqual(codes(okCells({ title: 'abc' })), []);
    assert.deepStrictEqual(codes(okCells({ title: 'x'.repeat(120) })), []);
    assert.deepStrictEqual(codes(okCells({ title: 'x'.repeat(121) })), ['TITLE_INVALID']);
    assert.deepStrictEqual(codes(okCells({ description: 'x'.repeat(2001) })), ['DESC_INVALID']);
    assert.deepStrictEqual(codes(okCells({ description: '' })), ['DESC_INVALID']);
    assert.deepStrictEqual(codes(okCells({ sku: '' })), ['SKU_REQUIRED']);
    assert.deepStrictEqual(codes(okCells({ sku: 'x'.repeat(65) })), ['SKU_TOO_LONG']);
  });

  await check('R4 MOQ / vazn / o\'lcham / birlik', () => {
    assert.deepStrictEqual(codes(okCells({ moq: 0 })), ['MOQ_INVALID']);
    assert.deepStrictEqual(codes(okCells({ moq: 1000001 })), ['MOQ_INVALID']);
    assert.deepStrictEqual(codes(okCells({ moq: 1000000 })), []);
    assert.deepStrictEqual(codes(okCells({ moq: '' })), []);
    assert.deepStrictEqual(codes(okCells({ weight_kg: '0' })), ['WEIGHT_INVALID']);
    assert.deepStrictEqual(codes(okCells({ weight_kg: '10001' })), ['WEIGHT_INVALID']);
    assert.deepStrictEqual(codes(okCells({ weight_kg: '10000' })), []);
    assert.deepStrictEqual(codes(okCells({ height_cm: '' })), ['DIMS_INVALID']);
    assert.deepStrictEqual(codes(okCells({ height_cm: 1001 })), ['DIMS_INVALID']);
    assert.deepStrictEqual(codes(okCells({ weight_kg: '' })), ['DIMS_NEED_WEIGHT']);
    assert.deepStrictEqual(codes(okCells({ unit: 'x'.repeat(21) })), ['UNIT_TOO_LONG']);
    assert.strictEqual(R.validateRow(okCells({ unit: '' }), 'wholesale').fields.unit, 'дона');
  });

  await check('R5 rasm URL: http(s) shart, javascript:/ftp:/login/port — xato; yo\'q — IMAGE_REQUIRED', () => {
    assert.deepStrictEqual(codes(okCells({ image_1: '' })), ['IMAGE_REQUIRED']);
    assert.deepStrictEqual(codes(okCells({ image_1: 'ftp://x.com/a.jpg' })), ['IMAGE_URL_INVALID']);
    assert.deepStrictEqual(codes(okCells({ image_1: 'javascript:alert(1)' })), ['IMAGE_URL_INVALID']);
    assert.deepStrictEqual(codes(okCells({ image_1: 'https://u:p@x.com/a.jpg' })), ['IMAGE_URL_INVALID']);
    assert.deepStrictEqual(codes(okCells({ image_1: 'http://x.com:8080/a.jpg' })), ['IMAGE_URL_INVALID']);
    const v = R.validateRow(okCells({ image_2: 'https://example.com/a.jpg', image_3: 'https://e.com/b.png' }), 'wholesale');
    assert.deepStrictEqual(v.imageSources, ['https://example.com/a.jpg', 'https://e.com/b.png']);
  });

  await check('R6 Xitoy: valyuta USD/CNY/bo\'sh; noto\'g\'ri — xato; ulgurjida USD — xato; yetkazish kuni', () => {
    assert.strictEqual(R.validateRow(okCells({ currency: 'USD' }), 'china').fields.currency, '$');
    assert.strictEqual(R.validateRow(okCells({ currency: 'cny' }), 'china').fields.currency, '¥');
    assert.strictEqual(R.validateRow(okCells({}), 'china').fields.currency, '');
    assert.deepStrictEqual(codes(okCells({ currency: 'EUR' }), 'china'), ['CURRENCY_INVALID']);
    assert.deepStrictEqual(codes(okCells({ currency: 'USD' }), 'wholesale'), ['CURRENCY_INVALID']);
    assert.deepStrictEqual(codes(okCells({ currency: 'UZS' }), 'wholesale'), []);
    assert.strictEqual(R.validateRow(okCells({ delivery_days: 20 }), 'china').fields.deliveryDays, 20);
    assert.deepStrictEqual(codes(okCells({ delivery_days: 366 }), 'china'), ['DELIVERY_DAYS_INVALID']);
  });

  await check('S1 varaq: 500 qator — o\'tadi, 501 — TOO_MANY_ROWS; namuna "#" va bo\'sh qator o\'qilmaydi', () => {
    const many = (n) => Array.from({ length: n }, (_, i) => okCells({ sku: `S-${i}` }));
    assert.strictEqual(R.validateSheet(sheetOf('wholesale', many(500)), 'wholesale').rows.length, 500);
    assert.strictEqual(R.validateSheet(sheetOf('wholesale', many(501)), 'wholesale').fileError, 'TOO_MANY_ROWS');
    const s = R.validateSheet(sheetOf('wholesale', [okCells({ sku: '#NAMUNA' }), {}, okCells()]), 'wholesale');
    assert.strictEqual(s.rows.length, 1);
    assert.strictEqual(s.rows[0].row, 4);
    assert.strictEqual(R.validateSheet(sheetOf('wholesale', [okCells({ sku: '#x' })]), 'wholesale').fileError, 'NO_ROWS');
  });

  await check('S2 takror SKU (registr/bo\'shliq farqsiz) — ikkala qator xato', () => {
    const s = R.validateSheet(sheetOf('wholesale', [okCells({ sku: 'ab 1' }), okCells({ sku: 'AB  1' }), okCells({ sku: 'C' })]), 'wholesale');
    assert.deepStrictEqual(s.rows.map((r) => r.errors), [['SKU_DUPLICATE'], ['SKU_DUPLICATE'], []]);
  });

  await check('S3 sarlavha: majburiy ustun yo\'q — HEADER_MISSING; faqat kalit yozilgan sarlavha ham ishlaydi', () => {
    const s = R.validateSheet({ header: ['[sku]', 'title'], rows: [] }, 'wholesale');
    assert.strictEqual(s.fileError, 'HEADER_MISSING');
    assert.deepStrictEqual(s.missing, ['description', 'price', 'image_1']);
    assert.strictEqual(R.keyOfHeader('Нарх* / Narx* / Цена* [price]'), 'price');
    assert.strictEqual(R.keyOfHeader('PRICE'), 'price');
    assert.strictEqual(R.keyOfHeader('Boshqa'), null);
    assert.strictEqual(R.validateSheet({ header: [], rows: [] }, 'mars').fileError, 'MARKET_INVALID');
  });

  await check('Q1 kunlik kvota: 10 — o\'tadi, 11 — rad; yangi kun — qayta 1', () => {
    let cur = null;
    for (let i = 1; i <= 10; i += 1) {
      const s = R.quotaStep(cur, '2026-11-19');
      assert.ok(s.allowed, `#${i}`);
      cur = s.next;
    }
    assert.strictEqual(R.quotaStep(cur, '2026-11-19').allowed, false);
    assert.deepStrictEqual(R.quotaStep(cur, '2026-11-20').next, { day: '2026-11-20', count: 1 });
    assert.strictEqual(R.tashkentDay(Date.UTC(2026, 10, 19, 19, 0)), '2026-11-20');
    assert.strictEqual(R.tashkentDay(Date.UTC(2026, 10, 19, 18, 59)), '2026-11-19');
  });

  await check('I1 ID deterministik: bir sotuvchi+bozor+SKU — bir ID; registr farqsiz; boshqa bozor — boshqa', () => {
    const a = R.productIdFor('998901112233', 'wholesale', 'ab-1');
    assert.strictEqual(a, R.productIdFor('998901112233', 'wholesale', ' AB-1 '));
    assert.notStrictEqual(a, R.productIdFor('998901112233', 'china', 'AB-1'));
    assert.notStrictEqual(a, R.productIdFor('998901112234', 'wholesale', 'AB-1'));
    assert.ok(/^imp_[a-f0-9]{32}$/.test(a));
    assert.ok(R.imageObjectName(a, 'https://x/y.jpg').startsWith(`${a}_`));
  });

  await check('C1 contentChanged / statusAfterUpdate', () => {
    const v = R.validateRow(okCells(), 'wholesale');
    const existing = { ...v.fields, importImages: v.imageSources.map((src) => ({ src, url: 'u' })), status: 'active' };
    assert.strictEqual(R.contentChanged(existing, v.fields, v.imageSources), false);
    assert.strictEqual(R.contentChanged({ ...existing, priceTiers: [{ minQty: 1, price: 1 }] }, v.fields, v.imageSources), true);
    assert.strictEqual(R.contentChanged(existing, v.fields, ['https://other/x.jpg']), true);
    assert.strictEqual(R.contentChanged({ ...existing, minOrderQty: undefined }, v.fields, v.imageSources), true);
    assert.strictEqual(R.statusAfterUpdate('active'), 'pending');
    assert.strictEqual(R.statusAfterUpdate('inactive'), 'inactive');
    assert.strictEqual(R.statusAfterUpdate('pending'), 'pending');
    // Ega 2026-11-20: narx-faqat o'zgarish - qayta moderatsiyasiz (holat saqlanadi).
    assert.strictEqual(R.moderationChanged({ ...existing, priceTiers: [{ minQty: 1, price: 1 }] }, v.fields, v.imageSources), false);
    assert.strictEqual(R.moderationChanged({ ...existing, title: 'Boshqa' }, v.fields, v.imageSources), true);
    assert.strictEqual(R.moderationChanged(existing, v.fields, ['https://other/x.jpg']), true);
    assert.strictEqual(R.statusAfterUpdate('active', true), 'active');
    assert.strictEqual(R.statusAfterUpdate('pending', true), 'pending');
    assert.strictEqual(R.statusAfterUpdate('inactive', true), 'inactive');
  });

  await check('C2 qidiruv tokenlari = klient AdSearchText.buildTokens (≤48)', () => {
    const t = R.clientSearchTokens('Ўрик қуритилган', 'Шакар');
    assert.deepStrictEqual(t, ['ўрик', "o'rik", 'қуритилган', 'quritilgan', 'шакар', 'shakar']);
    assert.ok(R.clientSearchTokens('a'.repeat(3) + ' ' + Array.from({ length: 60 }, (_, i) => `soz${i}`).join(' '), '').length <= 48);
  });

  await check('X1 shablon: 2 varaq, 3 tilli sarlavha; shablonni o\'zini o\'qisa — namuna o\'tkaziladi (NO_ROWS)', async () => {
    for (const market of ['wholesale', 'china']) {
      const buf = await X.buildTemplate(market);
      const p = await X.parseXlsx(buf);
      assert.ok(p.ok, JSON.stringify(p));
      assert.strictEqual(R.keyOfHeader(p.sheet.header[0]), 'sku');
      assert.strictEqual(p.sheet.header.some((h) => R.keyOfHeader(h) === 'currency'), market === 'china');
      assert.strictEqual(R.validateSheet(p.sheet, market).fileError, 'NO_ROWS');
      const wb = new ExcelJS.Workbook();
      await wb.xlsx.load(buf);
      assert.ok(wb.getWorksheet('Help'));
    }
  });

  await check('X2 xlsx o\'qish: raqam/matn/formula natijasi/richText; qator raqami Excel\'dagi', async () => {
    const h = header('wholesale');
    const keys = R.columnsFor('wholesale').map((c) => c.key);
    const row = (o) => keys.map((k) => o[k]);
    const buf = await xlsxOf(h, [
      row(okCells({ sku: 'K1' })),
      [],
      row(okCells({ sku: 'K2', price: { formula: '1000*2', result: 2000 }, title: { richText: [{ text: 'Шакар ' }, { text: 'оқ' }] } })),
    ]);
    const p = await X.parseXlsx(buf);
    assert.ok(p.ok);
    const s = R.validateSheet(p.sheet, 'wholesale');
    assert.deepStrictEqual(s.rows.map((r) => [r.row, r.errors]), [[2, []], [4, []]]);
    assert.strictEqual(s.rows[1].fields.priceTiers[0].price, 2000);
    assert.strictEqual(s.rows[1].fields.title, 'Шакар оқ');
  });

  await check('X3 xlsx emas / bo\'sh / 5 MB+ / zip-bomba — fayl xatosi', async () => {
    assert.strictEqual((await X.parseXlsx(Buffer.from('hello world, not a zip at all'))).code, 'FILE_NOT_XLSX');
    assert.strictEqual((await X.parseXlsx(Buffer.alloc(0))).code, 'FILE_EMPTY');
    assert.strictEqual((await X.parseXlsx(Buffer.alloc(R.LIMITS.maxFileBytes + 1, 1))).code, 'FILE_TOO_LARGE');
    // Soxta markaziy katalog: bitta yozuv 100 MB ochiladi deb aytadi.
    const buf = await xlsxOf(['[sku]'], []);
    const z = X.inspectZip(buf);
    assert.ok(z.ok);
    const bomb = Buffer.from(buf);
    const eocd = bomb.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
    const cd = bomb.readUInt32LE(eocd + 16);
    bomb.writeUInt32LE(100 * 1024 * 1024, cd + 24);
    assert.strictEqual(X.inspectZip(bomb).code, 'FILE_TOO_LARGE');
  });

  await check('G1 SSRF: xususiy/maxsus IP\'lar bloklanadi, ommaviy — yo\'q', () => {
    for (const ip of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254',
      '100.64.0.1', '0.0.0.0', '224.0.0.1', '::1', '::', 'fc00::1', 'fe80::1', '::ffff:127.0.0.1', '::ffff:10.0.0.1', 'garbage']) {
      assert.ok(IMG.isPrivateIp(ip), ip);
    }
    for (const ip of ['8.8.8.8', '172.32.0.1', '1.1.1.1', '2606:4700:4700::1111', '::ffff:8.8.8.8']) {
      assert.ok(!IMG.isPrivateIp(ip), ip);
    }
  });

  await check('G2 SSRF: localhost / metadata / IP literal / DNS -> ichki manzil — IMAGE_BLOCKED_HOST', async () => {
    const pub = async () => [{ address: '93.184.216.34', family: 4 }];
    const evil = async () => [{ address: '93.184.216.34', family: 4 }, { address: '10.0.0.5', family: 4 }];
    const blocked = async (url, resolve) => assert.rejects(IMG.fetchImageBytes(url, { resolve }), (e) => e.code === 'IMAGE_BLOCKED_HOST');
    await blocked('http://localhost/a.jpg', pub);
    await blocked('http://metadata.google.internal/computeMetadata/v1/', pub);
    await blocked('http://169.254.169.254/latest/meta-data', pub);
    await blocked('http://127.0.0.1/a.jpg', pub);
    await blocked('http://[::1]/a.jpg', pub);
    await blocked('http://rebind.example.com/a.jpg', evil);
    await assert.rejects(IMG.fetchImageBytes('file:///etc/passwd'), (e) => e.code === 'IMAGE_URL_INVALID');
    await assert.rejects(IMG.fetchImageBytes('http://x.com:22/a'), (e) => e.code === 'IMAGE_URL_INVALID');
  });

  // Eslatma: redirect yo'li (har hop'da vetHost) bu yerda tarmoq orqali sinalmagan — 80/443 dan
  // boshqa port URL darajasida rad etiladi, mahalliy test serveri esa 80-portda tura olmaydi.
  await check('G3 mahalliy server noodatiy portda — URL darajasida rad (port skanerlash yo\'q)', async () => {
    const srv = http.createServer((req, res) => { res.writeHead(302, { Location: 'http://127.0.0.1/secret' }); res.end(); });
    await new Promise((r) => srv.listen(0, '127.0.0.1', r));
    const port = srv.address().port;
    try {
      // Port 80/443 dan boshqa — URL darajasida rad: SSRF port skanerlash ham yo'q.
      await assert.rejects(IMG.fetchImageBytes(`http://127.0.0.1:${port}/a.jpg`), (e) => e.code === 'IMAGE_URL_INVALID');
    } finally { srv.close(); }
  });

  await check('P1 qayta kodlash: PNG -> JPEG, katta tomoni ≤1600; rasm emas — IMAGE_NOT_IMAGE', async () => {
    const sharp = require('sharp');
    const png = await sharp({ create: { width: 3000, height: 1000, channels: 4, background: { r: 255, g: 0, b: 0, alpha: 0.5 } } }).png().toBuffer();
    const out = await IMG.reencodeImage(png);
    const m = await sharp(out).metadata();
    assert.strictEqual(m.format, 'jpeg');
    assert.strictEqual(m.width, 1600);
    assert.ok(m.height <= 1600);
    await assert.rejects(IMG.reencodeImage(Buffer.from('<html>not an image</html>')), (e) => e.code === 'IMAGE_NOT_IMAGE');
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main();
