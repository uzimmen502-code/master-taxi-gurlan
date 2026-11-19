/**
 * Улгуржи Excel юклаш — callable'лар (Preview/Confirm/Template), Firestore Emulator.
 * Storage ва расм юклаб олиш — сохта (fileStore/processImage DI), Firestore — ҳақиқий эмулятор.
 *
 *   firebase emulators:exec --only firestore --project demo-ulg-import \
 *     "node test/wholesale_import_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ulg-import';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const ExcelJS = require('exceljs');
const R = require('../wholesale_import_rules');
const { attachWholesaleImport } = require('../wholesale_import');

const db = admin.firestore();
const SELLER = '998901110001';
const PENDING = '998901110002';
const NOADDR = '998901110003';
const OTHER = '998901110004';

const files = new Map();
const deleted = [];
let imageCalls = [];
let clock = Date.UTC(2026, 10, 19, 6, 0);
const fakeStore = {
  async saveFile(p, buf) { files.set(p, Buffer.from(buf)); },
  async readFile(p) { if (!files.has(p)) throw new Error('nf'); return files.get(p); },
  async saveImage(p) { files.set(p, Buffer.from('jpg')); return `https://firebasestorage.googleapis.com/v0/b/demo/o/${encodeURIComponent(p)}?alt=media&token=t`; },
  async deleteByUrl(u, prefix) { const p = decodeURIComponent(u.split('/o/')[1].split('?')[0]); if (p.startsWith(prefix)) deleted.push(p); },
};
const processImage = async (url) => {
  imageCalls.push(url);
  if (url.includes('bad')) { const e = new Error('x'); e.code = 'IMAGE_BLOCKED_HOST'; throw e; }
  return Buffer.from('jpeg');
};
const local = {};
attachWholesaleImport(local, {
  functions, db, admin,
  callerPhone: (c) => String(c.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v).replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
  fileStore: fakeStore, processImage, now: () => clock,
});

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => local[name].run(data, ctxOf(who));
let reqN = 0;
const rid = () => `req-${String(++reqN).padStart(8, '0')}`;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}

const cols = (market) => R.columnsFor(market);
async function xlsxB64(market, rows) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Products');
  ws.addRow(cols(market).map(R.headerText));
  for (const r of rows) ws.addRow(cols(market).map((c) => r[c.key]));
  return Buffer.from(await wb.xlsx.writeBuffer()).toString('base64');
}
const row = (over = {}) => ({
  sku: 'A-1', title: 'Ун олий нав', description: 'Яхши ун', price: 350000, unit: 'қоп', moq: 10,
  weight_kg: 50, image_1: 'https://img.example.com/a.jpg', ...over,
});
const product = async (sku, market = 'wholesale') => {
  const s = await db.collection('wholesale_products').doc(R.productIdFor(SELLER, market, sku)).get();
  return s.exists ? s.data() : null;
};

async function main() {
  await clearEmulator();
  await db.collection('wholesale_sellers').doc(SELLER).set({ phone: SELLER, companyName: 'Un savdo', approvalStatus: 'approved', districtId: 'gurlan', regionId: 'xorazm' });
  await db.collection('wholesale_sellers').doc(PENDING).set({ phone: PENDING, companyName: 'P', approvalStatus: 'pending', districtId: 'gurlan' });
  await db.collection('wholesale_sellers').doc(NOADDR).set({ phone: NOADDR, companyName: 'N', approvalStatus: 'approved' });

  await check('E0 index.js callable\'larni eksport qiladi', () => {
    for (const n of ['wholesaleImportTemplate', 'wholesaleImportPreview', 'wholesaleImportConfirm']) assert.ok(fns[n], n);
  });

  await check('A1 faqat tasdiqlangan + manzilli sotuvchi; auth shart', async () => {
    const b64 = await xlsxB64('wholesale', [row()]);
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: rid() }, PENDING), 'SELLER_NOT_APPROVED');
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: rid() }, OTHER), 'SELLER_NOT_APPROVED');
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: rid() }, NOADDR), 'SHIP_FROM_REQUIRED');
    await assert.rejects(local.wholesaleImportPreview.run({}, {}));
    await expectCode(call('wholesaleImportPreview', { market: 'mars', fileBase64: b64, clientRequestId: rid() }, SELLER), 'MARKET_INVALID');
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: 'x' }, SELLER), 'REQUEST_ID_INVALID');
  });

  await check('T1 shablon: base64 xlsx, sotuvchiga', async () => {
    const r = await call('wholesaleImportTemplate', { market: 'china' }, SELLER);
    assert.strictEqual(r.fileName, 'ava_china_products.xlsx');
    assert.ok(Buffer.from(r.base64, 'base64').length > 1000);
    await expectCode(call('wholesaleImportTemplate', { market: 'wholesale' }, PENDING), 'SELLER_NOT_APPROVED');
  });

  let batchId;
  await check('P1 preview: hech narsa yozilmaydi; qator xatolari raqam bilan; takror chaqiruv — kvota oshmaydi', async () => {
    const b64 = await xlsxB64('wholesale', [
      row(), row({ sku: 'B-2', price: 0 }), row({ sku: 'C-3', image_1: 'ftp://x/y' }),
      row({ sku: 'D-4' }), row({ sku: 'd-4' }), row({ sku: 'E-5', price: 12.5 }), row({ sku: 'F-6', image_1: 'https://bad.example.com/x.jpg' }),
    ]);
    const req = rid();
    const r = await call('wholesaleImportPreview', { market: 'wholesale', fileName: 'narx.xlsx', fileBase64: b64, clientRequestId: req }, SELLER);
    batchId = r.batchId;
    assert.deepStrictEqual(r.counts, { total: 7, ready: 2, errors: 5, create: 2, update: 0, unchanged: 0 });
    const byRow = Object.fromEntries(r.rows.map((x) => [x.row, x.errors]));
    assert.deepStrictEqual(byRow, { 2: [], 3: ['PRICE_INVALID'], 4: ['IMAGE_URL_INVALID'], 5: ['SKU_DUPLICATE'], 6: ['SKU_DUPLICATE'], 7: ['PRICE_NOT_INT'], 8: [] });
    assert.strictEqual(r.quota.used, 1);
    assert.strictEqual(await product('A-1'), null);
    const again = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: req }, SELLER);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual(again.batchId, batchId);
    assert.strictEqual((await db.collection('wholesale_import_quota').doc(SELLER).get()).data().count, 1);
    assert.ok(files.has(`wholesale_imports/${SELLER}/${batchId}.xlsx`));
  });

  await check('C1 confirm: yaratiladi (pending, auto-approve OFF), rasm xatosi — qator xatosi; boshqa sotuvchi tasdiqlay olmaydi', async () => {
    await db.collection('wholesale_sellers').doc(OTHER).set({ phone: OTHER, companyName: 'O', approvalStatus: 'approved', districtId: 'x' });
    await expectCode(call('wholesaleImportConfirm', { batchId }, OTHER), 'NOT_OWNER');
    const r = await call('wholesaleImportConfirm', { batchId }, SELLER);
    assert.strictEqual(r.status, 'done');
    assert.strictEqual(r.counts.created, 1);
    assert.strictEqual(r.counts.error, 6);
    assert.deepStrictEqual(r.rows.find((x) => x.row === 8).errors, ['IMAGE_BLOCKED_HOST']);
    const p = await product('A-1');
    assert.strictEqual(p.status, 'pending');
    assert.strictEqual(p.sellerId, SELLER);
    assert.strictEqual(p.sellerCompanyName, 'Un savdo');
    assert.strictEqual(p.market, 'wholesale');
    assert.deepStrictEqual(p.priceTiers, [{ minQty: 1, price: 350000 }]);
    assert.strictEqual(p.minOrderQty, 10);
    assert.strictEqual(p.unitWeightG, 50000);
    assert.strictEqual(p.views, 0);
    assert.deepStrictEqual(p.videoClipIds, []);
    assert.strictEqual(p.imageUrls.length, 1);
    assert.ok(p.imageUrls[0].includes(encodeURIComponent(`wholesale_products/${SELLER}/`)));
    assert.strictEqual(p.sku, 'A-1');
    assert.strictEqual(p.importBatchId, batchId);
    assert.ok(p.createdAt && p.searchTokens.length > 0);
    assert.strictEqual(await product('F-6'), null);
    const b = (await db.collection('wholesale_imports').doc(batchId).get()).data();
    assert.strictEqual(b.status, 'done');
    assert.strictEqual(b.result.counts.created, 1);
  });

  await check('C2 confirm takror (idempotent): saqlangan natija, ikkinchi yozuv yo\'q', async () => {
    imageCalls = [];
    const r = await call('wholesaleImportConfirm', { batchId }, SELLER);
    assert.strictEqual(r.duplicate, true);
    assert.strictEqual(r.counts.created, 1);
    assert.deepStrictEqual(imageCalls, []);
  });

  await check('U1 qayta yuklash: o\'zgarmagan — unchanged (rasm qayta yuklanmaydi); narx o\'zgardi — updated, pending', async () => {
    await db.collection('wholesale_products').doc(R.productIdFor(SELLER, 'wholesale', 'A-1')).update({ status: 'active' });
    const same = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', [row()]), clientRequestId: rid() }, SELLER);
    assert.strictEqual(same.counts.unchanged, 1);
    imageCalls = [];
    const c = await call('wholesaleImportConfirm', { batchId: same.batchId }, SELLER);
    assert.strictEqual(c.counts.unchanged, 1);
    assert.deepStrictEqual(imageCalls, []);
    assert.strictEqual((await product('A-1')).status, 'active');

    const upd = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', [row({ price: 360000, moq: '' })]), clientRequestId: rid() }, SELLER);
    assert.strictEqual(upd.counts.update, 1);
    const c2 = await call('wholesaleImportConfirm', { batchId: upd.batchId }, SELLER);
    assert.strictEqual(c2.counts.updated, 1);
    assert.deepStrictEqual(imageCalls, [], 'rasm manbasi o\'zgarmadi — kesh');
    const p = await product('A-1');
    assert.strictEqual(p.status, 'pending');
    assert.deepStrictEqual(p.priceTiers, [{ minQty: 1, price: 360000 }]);
    assert.ok(!('minOrderQty' in p), 'fayldan olib tashlangan MOQ o\'chadi');
    assert.strictEqual(p.createdAt.toMillis() > 0, true);
  });

  await check('U2 rasm almashdi — yangisi yuklanadi, eskisi o\'chiriladi; inactive — inactive qoladi', async () => {
    await db.collection('wholesale_products').doc(R.productIdFor(SELLER, 'wholesale', 'A-1')).update({ status: 'inactive' });
    const old = (await product('A-1')).imageUrls[0];
    imageCalls = [];
    const r = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', [row({ price: 360000, moq: '', image_1: 'https://img.example.com/b.jpg' })]), clientRequestId: rid() }, SELLER);
    await call('wholesaleImportConfirm', { batchId: r.batchId }, SELLER);
    const p = await product('A-1');
    assert.deepStrictEqual(imageCalls, ['https://img.example.com/b.jpg']);
    assert.notStrictEqual(p.imageUrls[0], old);
    assert.strictEqual(p.status, 'inactive');
    assert.ok(deleted.some((d) => old.includes(encodeURIComponent(d))));
  });

  await check('U3 sotuvchi qadoq qo\'shgan mahsulot — SKU_HAS_PACKS, tegilmaydi', async () => {
    await db.collection('wholesale_products').doc(R.productIdFor(SELLER, 'wholesale', 'A-1')).update({ packs: [{ id: 'p1' }] });
    const r = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', [row({ price: 1 })]), clientRequestId: rid() }, SELLER);
    assert.deepStrictEqual(r.rows[0].errors, ['SKU_HAS_PACKS']);
  });

  await check('AA1 auto-approve ON: yangi — active + moderatedBy auto; Xitoy valyutasi', async () => {
    await db.collection('settings').doc('app').set({ wholesaleProductAutoApprove: true });
    const r = await call('wholesaleImportPreview', { market: 'china', fileBase64: await xlsxB64('china', [row({ sku: 'CN-1', price: 25, currency: 'USD', delivery_days: 20 })]), clientRequestId: rid() }, SELLER);
    await call('wholesaleImportConfirm', { batchId: r.batchId }, SELLER);
    const p = await product('CN-1', 'china');
    assert.strictEqual(p.status, 'active');
    assert.strictEqual(p.moderatedBy, 'auto');
    assert.strictEqual(p.market, 'china');
    assert.strictEqual(p.currency, '$');
    assert.strictEqual(p.deliveryDays, 20);
  });

  await check('F1 fayl xatolari: xlsx emas, sarlavha yo\'q, 501 qator', async () => {
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: Buffer.from('not xlsx data here').toString('base64'), clientRequestId: rid() }, SELLER), 'FILE_NOT_XLSX');
    const many = Array.from({ length: 501 }, (_, i) => row({ sku: `M-${i}` }));
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', many), clientRequestId: rid() }, SELLER), 'TOO_MANY_ROWS');
  });

  await check('Q1 kunlik chegara: 10-chi o\'tadi, 11-chi DAILY_LIMIT; ertasi kun — yana', async () => {
    const used = (await db.collection('wholesale_import_quota').doc(SELLER).get()).data().count;
    const b64 = await xlsxB64('wholesale', [row({ sku: 'Q-1' })]);
    for (let i = used; i < 10; i += 1) {
      await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: rid() }, SELLER);
    }
    assert.strictEqual((await db.collection('wholesale_import_quota').doc(SELLER).get()).data().count, 10);
    await expectCode(call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: rid() }, SELLER), 'DAILY_LIMIT');
    clock += 24 * 3600 * 1000;
    const r = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: b64, clientRequestId: rid() }, SELLER);
    assert.strictEqual(r.quota.used, 1);
  });

  await check('B1 eskirgan preview (24 soat+) — BATCH_EXPIRED; noto\'g\'ri batchId — BATCH_NOT_FOUND', async () => {
    const r = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', [row({ sku: 'X-1' })]), clientRequestId: rid() }, SELLER);
    clock += 24 * 3600 * 1000 + 1;
    await expectCode(call('wholesaleImportConfirm', { batchId: r.batchId }, SELLER), 'BATCH_EXPIRED');
    await expectCode(call('wholesaleImportConfirm', { batchId: 'wsi_000000000000000000000000' }, SELLER), 'BATCH_NOT_FOUND');
    await expectCode(call('wholesaleImportConfirm', { batchId: '../x' }, SELLER), 'BATCH_NOT_FOUND');
  });

  await check('B2 parallel confirm: ijara band — BATCH_BUSY', async () => {
    const r = await call('wholesaleImportPreview', { market: 'wholesale', fileBase64: await xlsxB64('wholesale', [row({ sku: 'L-1' })]), clientRequestId: rid() }, SELLER);
    await db.collection('wholesale_imports').doc(r.batchId).update({ status: 'processing', leaseUntilMs: clock + 60000 });
    await expectCode(call('wholesaleImportConfirm', { batchId: r.batchId }, SELLER), 'BATCH_BUSY');
    await db.collection('wholesale_imports').doc(r.batchId).update({ leaseUntilMs: clock - 1 });
    const c = await call('wholesaleImportConfirm', { batchId: r.batchId }, SELLER);
    assert.strictEqual(c.counts.created, 1);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
