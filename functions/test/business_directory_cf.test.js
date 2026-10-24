/**
 * BIZNES XARITASI — callable'lar, HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-business-cf \
 *     "node test/business_directory_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-business-cf';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { normalizeInput, changedKeys, CATEGORIES, LIMITS, EDITABLE } = require('../business_directory');
const { encode } = require('../geo_hash');

const db = admin.firestore();
const ADMIN = '998915000001';
const OWNER = '998912000001';
const OTHER = '998912000002';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
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
const biz = async (id) => (await db.collection('businesses').doc(id).get()).data();

const BASE = {
  name: 'Gurlan Avto-moyka', category: 'auto', subtype: 'avto-moyka', description: '24/7',
  phone: '+998 90 123-45-67', address: 'Gurlan, Navoiy ko\'chasi 5', lat: 41.8442, lng: 60.3925,
  openingHours: '08:00-22:00', website: 'https://example.uz',
};

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(OWNER).set({ role: 'user' });
  await db.collection('users').doc(OTHER).set({ role: 'user' });
  await db.collection('geo_districts').doc('d_gurlan').set({ regionId: 'r_xorazm', name: 'Gurlan' });

  const fail = (status, code, msg) => Object.assign(new Error(msg || code), { details: { code } });

  await check('P1 normalizeInput: tozalaydi, geohash serverda hisoblanadi, telefon faqat raqam', () => {
    const n = normalizeInput({ ...BASE, name: '  Gurlan Avto-moyka  ' }, fail);
    assert.strictEqual(n.name, 'Gurlan Avto-moyka');
    assert.strictEqual(n.phone, '998901234567');
    assert.strictEqual(n.geohash, encode(41.8442, 60.3925, 9));
    assert.strictEqual(n.geohash4, encode(41.8442, 60.3925, 4));
    assert.strictEqual(n.regionId, '');
  });

  await check('P2 normalizeInput: chegaralar (nom, tur, koordinata, telefon, matn, hudud juftligi)', () => {
    const code = (over) => { try { normalizeInput({ ...BASE, ...over }, fail); return 'OK'; } catch (e) { return e.details.code; } };
    assert.strictEqual(code({ name: 'A' }), 'BUSINESS_NAME_INVALID');
    assert.strictEqual(code({ name: 'x'.repeat(LIMITS.nameMax + 1) }), 'BUSINESS_NAME_INVALID');
    assert.strictEqual(code({ name: 'x'.repeat(LIMITS.nameMax) }), 'OK'); // chegara: aynan max
    assert.strictEqual(code({ category: 'food_old' }), 'BUSINESS_CATEGORY_INVALID');
    assert.strictEqual(code({ category: undefined }), 'BUSINESS_CATEGORY_INVALID');
    assert.strictEqual(code({ lat: '41.8' }), 'BUSINESS_LOCATION_INVALID');
    assert.strictEqual(code({ lat: NaN }), 'BUSINESS_LOCATION_INVALID');
    assert.strictEqual(code({ lat: 10, lng: 60 }), 'BUSINESS_LOCATION_INVALID'); // O'zbekiston tashqarisi
    assert.strictEqual(code({ lng: 80 }), 'BUSINESS_LOCATION_INVALID');
    assert.strictEqual(code({ phone: '12345' }), 'BUSINESS_PHONE_INVALID');
    assert.strictEqual(code({ phone: '1'.repeat(16) }), 'BUSINESS_PHONE_INVALID');
    assert.strictEqual(code({ description: 'x'.repeat(LIMITS.descriptionMax + 1) }), 'BUSINESS_FIELD_INVALID');
    assert.strictEqual(code({ regionId: 'r1' }), 'GEO_DISTRICT_INVALID'); // juft emas
    assert.strictEqual(code({ regionId: 'r/1', districtId: 'd1' }), 'GEO_DISTRICT_INVALID');
    assert.strictEqual(code({ regionId: 'r1', districtId: 'd1' }), 'OK');
  });

  await check('P3 kategoriyalar ro\'yxati: 14 ta, takrorsiz, "other" bor (Dart paritet testi shu ro\'yxatni qulflaydi)', () => {
    assert.strictEqual(CATEGORIES.length, 14);
    assert.strictEqual(new Set(CATEGORIES).size, 14);
    assert.ok(CATEGORIES.includes('other'));
  });

  await check('P4 changedKeys: faqat tahrirlanadigan maydonlar', () => {
    const cur = { ...normalizeInput(BASE, fail), ownerId: OWNER, status: 'active' };
    assert.deepStrictEqual(changedKeys(cur, normalizeInput(BASE, fail)), []);
    assert.deepStrictEqual(changedKeys(cur, normalizeInput({ ...BASE, name: 'Boshqa nom' }, fail)), ['name']);
    assert.ok(!EDITABLE.includes('ownerId') && !EDITABLE.includes('status'));
  });

  let bizId;
  await check('C1 egasi yaratadi: ownerId tokendan, status active, geohash serverda', async () => {
    const r = await call('upsertMyBusiness', { ...BASE, clientRequestId: 'req-00000001' }, OWNER);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.duplicate, false);
    bizId = r.businessId;
    assert.strictEqual(bizId, `${OWNER}_req-00000001`);
    const d = await biz(bizId);
    assert.strictEqual(d.ownerId, OWNER);
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.geohash4, encode(41.8442, 60.3925, 4));
    assert.ok(d.createdAt && d.updatedAt);
  });

  await check('C2 mijoz ownerId/status/geohash yuborsa ham e\'tibor berilmaydi (18-band)', async () => {
    const r = await call('upsertMyBusiness', {
      ...BASE, clientRequestId: 'req-00000002', ownerId: OTHER, status: 'hidden', geohash: 'zzzz', geohash4: 'zzzz',
    }, OWNER);
    const d = await biz(r.businessId);
    assert.strictEqual(d.ownerId, OWNER);
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.geohash4, encode(41.8442, 60.3925, 4));
  });

  await check('C3 takroriy chaqiruv (retry) — bitta hujjat, duplicate:true, maydonlar o\'zgarmaydi (21-band)', async () => {
    const r = await call('upsertMyBusiness', { ...BASE, name: 'Boshqa nom', clientRequestId: 'req-00000001' }, OWNER);
    assert.strictEqual(r.duplicate, true);
    assert.strictEqual(r.businessId, bizId);
    assert.strictEqual((await biz(bizId)).name, 'Gurlan Avto-moyka');
    assert.strictEqual((await db.collection('businesses').where('ownerId', '==', OWNER).get()).size, 2);
  });

  await check('C4 loginsiz / telefon tokensiz rad; clientRequestId shart', async () => {
    await assert.rejects(fns.upsertMyBusiness.run({ ...BASE, clientRequestId: 'req-00000009' }, {}));
    await expectCode(call('upsertMyBusiness', { ...BASE }, OWNER), 'REQUEST_ID_INVALID');
    await expectCode(call('upsertMyBusiness', { ...BASE, clientRequestId: 'x' }, OWNER), 'REQUEST_ID_INVALID');
  });

  await check('C5 hudud: mavjud tuman + o\'z viloyati — qabul; yo\'q yoki boshqa viloyat — rad', async () => {
    const ok = await call('upsertMyBusiness', { ...BASE, clientRequestId: 'req-00000003', regionId: 'r_xorazm', districtId: 'd_gurlan' }, OWNER);
    assert.strictEqual((await biz(ok.businessId)).districtId, 'd_gurlan');
    await expectCode(call('upsertMyBusiness', { ...BASE, clientRequestId: 'req-00000004', regionId: 'r_xorazm', districtId: 'd_yoq' }, OWNER), 'GEO_DISTRICT_INVALID');
    await expectCode(call('upsertMyBusiness', { ...BASE, clientRequestId: 'req-00000005', regionId: 'r_boshqa', districtId: 'd_gurlan' }, OWNER), 'GEO_DISTRICT_INVALID');
  });

  await check('C6 egasi o\'zinikini tahrirlaydi; o\'zgarish bo\'lmasa changed:false; geohash yangilanadi', async () => {
    const same = await call('upsertMyBusiness', { ...BASE, businessId: bizId }, OWNER);
    assert.strictEqual(same.changed, false);
    const r = await call('upsertMyBusiness', { ...BASE, businessId: bizId, name: 'Yangi nom', lat: 41.3, lng: 69.2 }, OWNER);
    assert.strictEqual(r.changed, true);
    const d = await biz(bizId);
    assert.strictEqual(d.name, 'Yangi nom');
    assert.strictEqual(d.geohash4, encode(41.3, 69.2, 4));
    assert.strictEqual(d.ownerId, OWNER);
  });

  await check('C7 begona yozuvni tahrirlash/o\'chirish rad; yo\'q yozuv — NOT_FOUND', async () => {
    await expectCode(call('upsertMyBusiness', { ...BASE, businessId: bizId, name: 'Hack' }, OTHER), 'BUSINESS_NOT_OWNER');
    await expectCode(call('deleteMyBusiness', { businessId: bizId }, OTHER), 'BUSINESS_NOT_OWNER');
    await expectCode(call('upsertMyBusiness', { ...BASE, businessId: 'yoq_yozuv' }, OWNER), 'BUSINESS_NOT_FOUND');
    assert.strictEqual((await biz(bizId)).name, 'Yangi nom');
  });

  await check('C8 bir egada limit: maxPerOwner dan keyin BUSINESS_LIMIT_REACHED', async () => {
    const have = (await db.collection('businesses').where('ownerId', '==', OWNER).get()).size;
    for (let i = have; i < LIMITS.maxPerOwner; i += 1) {
      await call('upsertMyBusiness', { ...BASE, clientRequestId: `fill-${String(i).padStart(8, '0')}` }, OWNER);
    }
    await expectCode(call('upsertMyBusiness', { ...BASE, clientRequestId: 'over-00000001' }, OWNER), 'BUSINESS_LIMIT_REACHED');
    // boshqa egaga ta'sir qilmaydi
    const r = await call('upsertMyBusiness', { ...BASE, clientRequestId: 'req-00000001' }, OTHER);
    assert.strictEqual(r.duplicate, false);
  });

  await check('C9 egasi o\'chiradi (idempotent: ikkinchi marta deleted:false)', async () => {
    const r = await call('deleteMyBusiness', { businessId: bizId }, OWNER);
    assert.strictEqual(r.deleted, true);
    assert.strictEqual((await biz(bizId)), undefined);
    assert.strictEqual((await call('deleteMyBusiness', { businessId: bizId }, OWNER)).deleted, false);
    // o'chirgandan keyin joy bo'shadi
    const again = await call('upsertMyBusiness', { ...BASE, clientRequestId: 'over-00000002' }, OWNER);
    assert.strictEqual(again.duplicate, false);
  });

  const target = `${OTHER}_req-00000001`;
  await check('A1 admin: faqat admin; sabab shart; mijoz rad', async () => {
    await assert.rejects(call('adminUpdateBusiness', { ...BASE, businessId: target, reason: 'tuzatish' }, OWNER));
    await assert.rejects(call('adminDeleteBusiness', { businessId: target, reason: 'tuzatish' }, OWNER));
    await expectCode(call('adminUpdateBusiness', { ...BASE, businessId: target, reason: '' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminDeleteBusiness', { businessId: target, reason: 'x' }, ADMIN), 'REASON_REQUIRED');
  });

  await check('A2 admin tahrirlaydi: ownerId o\'zgarmaydi, audit changedKeys bilan; o\'zgarishsiz — audit yo\'q', async () => {
    const before = await db.collection('admin_audit').where('kind', '==', 'business_update').get();
    const noop = await call('adminUpdateBusiness', { ...BASE, businessId: target, reason: 'tekshirish' }, ADMIN);
    assert.strictEqual(noop.changed, false);
    const r = await call('adminUpdateBusiness', { ...BASE, businessId: target, name: 'Admin tuzatgan nom', reason: 'imlo xatosi' }, ADMIN);
    assert.strictEqual(r.changed, true);
    const d = await biz(target);
    assert.strictEqual(d.name, 'Admin tuzatgan nom');
    assert.strictEqual(d.ownerId, OTHER);
    assert.strictEqual(d.updatedBy, ADMIN);
    const audit = await db.collection('admin_audit').where('kind', '==', 'business_update').get();
    assert.strictEqual(audit.size, before.size + 1);
    const a = audit.docs.map((x) => x.data()).find((x) => x.target === target);
    assert.deepStrictEqual(a.changedKeys, ['name']);
    assert.strictEqual(a.actor, ADMIN);
    assert.strictEqual(a.reason, 'imlo xatosi');
  });

  await check('A3 admin yozuv YARATA olmaydi: yo\'q businessId — NOT_FOUND (B-1)', async () => {
    await expectCode(call('adminUpdateBusiness', { ...BASE, businessId: 'yangi_id_123', reason: 'qo\'shish' }, ADMIN), 'BUSINESS_NOT_FOUND');
    assert.strictEqual(await biz('yangi_id_123'), undefined);
  });

  await check('A4 admin o\'chiradi: audit snapshot bilan; takror — deleted:false, audit ortmaydi', async () => {
    const r = await call('adminDeleteBusiness', { businessId: target, reason: 'soxta e\'lon' }, ADMIN);
    assert.strictEqual(r.deleted, true);
    assert.strictEqual(await biz(target), undefined);
    const audits = (await db.collection('admin_audit').where('kind', '==', 'business_delete').get()).docs.map((x) => x.data());
    assert.strictEqual(audits.length, 1);
    assert.strictEqual(audits[0].target, target);
    assert.strictEqual(audits[0].snapshot.name, 'Admin tuzatgan nom');
    const again = await call('adminDeleteBusiness', { businessId: target, reason: 'soxta e\'lon' }, ADMIN);
    assert.strictEqual(again.deleted, false);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'business_delete').get()).size, 1);
  });

  // ── Admin QO'SHA oladi (ega qarori 2026-10-23) ──────────────────────────
  await check('A5 adminCreateBusiness: faqat admin; sabab va clientRequestId shart; mijoz rad', async () => {
    await assert.rejects(call('adminCreateBusiness', { ...BASE, clientRequestId: 'adm-00000001', reason: 'qo\'shish' }, OWNER));
    await expectCode(call('adminCreateBusiness', { ...BASE, clientRequestId: 'adm-00000001', reason: '' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminCreateBusiness', { ...BASE, reason: 'qo\'shish' }, ADMIN), 'REQUEST_ID_INVALID');
    await expectCode(call('adminCreateBusiness', { ...BASE, name: 'A', clientRequestId: 'adm-00000001', reason: 'qo\'shish' }, ADMIN), 'BUSINESS_NAME_INVALID');
  });

  await check('A6 egasiz yaratish: ownerId "admin", status active, geohash serverda, audit; takror — duplicate', async () => {
    const r = await call('adminCreateBusiness', { ...BASE, clientRequestId: 'adm-00000002', reason: 'telefon orqali olingan' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.duplicate, r.businessId], [true, false, 'admin_adm-00000002']);
    const d = await biz(r.businessId);
    assert.strictEqual(d.ownerId, 'admin');
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.source, 'admin');
    assert.strictEqual(d.createdBy, ADMIN);
    assert.strictEqual(d.geohash4, encode(41.8442, 60.3925, 4));
    const a = (await db.collection('admin_audit').where('kind', '==', 'business_create').get()).docs.map((x) => x.data());
    assert.strictEqual(a.length, 1);
    assert.deepStrictEqual([a[0].target, a[0].actor, a[0].reason, a[0].ownerId], ['admin_adm-00000002', ADMIN, 'telefon orqali olingan', 'admin']);
    const again = await call('adminCreateBusiness', { ...BASE, name: 'Boshqa', clientRequestId: 'adm-00000002', reason: 'qayta' }, ADMIN);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual((await biz(r.businessId)).name, BASE.name, 'takror yozmaydi');
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'business_create').get()).size, 1);
  });

  await check('A7 egasiz ob\'ektni hech bir foydalanuvchi o\'zgartira/o\'chira olmaydi; admin tahrirlaydi', async () => {
    await expectCode(call('upsertMyBusiness', { ...BASE, businessId: 'admin_adm-00000002', name: 'Hack' }, OWNER), 'BUSINESS_NOT_OWNER');
    await expectCode(call('deleteMyBusiness', { businessId: 'admin_adm-00000002' }, OWNER), 'BUSINESS_NOT_OWNER');
    const r = await call('adminUpdateBusiness', { ...BASE, businessId: 'admin_adm-00000002', name: 'Admin tuzatdi', reason: 'imlo' }, ADMIN);
    assert.strictEqual(r.changed, true);
  });

  await check('A8 ownerPhone bilan: ob\'ekt shu foydalanuvchiniki (o\'zi tahrirlaydi); noto\'g\'ri telefon — rad; limit adminga tegmaydi', async () => {
    const r = await call('adminCreateBusiness', { ...BASE, clientRequestId: 'adm-00000003', ownerPhone: '+998 91 200-00-01', reason: 'egasi uchun' }, ADMIN);
    assert.strictEqual((await biz(r.businessId)).ownerId, '998912000001');
    const edit = await call('upsertMyBusiness', { ...BASE, businessId: r.businessId, name: 'Egasi tahrirladi' }, OWNER);
    assert.strictEqual(edit.changed, true);
    await expectCode(call('adminCreateBusiness', { ...BASE, clientRequestId: 'adm-00000004', ownerPhone: '12345', reason: 'x1x' }, ADMIN), 'BUSINESS_OWNER_INVALID');
    // OWNER'da allaqachon limitga yetgan holat bo'lmasa ham: admin yaratishi egasining kvotasiga ta'sir qilmaydi (kod yo'li alohida)
    for (let i = 0; i < LIMITS.maxPerOwner + 2; i += 1) {
      await call('adminCreateBusiness', { ...BASE, clientRequestId: `adm-bulk-${String(i).padStart(4, '0')}`, ownerPhone: OTHER, reason: 'kvota sinovi' }, ADMIN);
    }
    assert.ok((await db.collection('businesses').where('ownerId', '==', OTHER).get()).size > LIMITS.maxPerOwner, 'admin limitdan ortiq qo\'sha oladi');
  });

  // ───────── Объект маҳсулотлари (tv_shop_items + businessId): админ таҳрир/ўчириш, audit ─────────
  const items = db.collection('tv_shop_items');
  const auditOf = async (kind, target) =>
    (await db.collection('admin_audit').where('kind', '==', kind).where('target', '==', target).get()).docs.map((d) => d.data());
  await items.doc('p_biz').set({ ownerPhone: OWNER, title: 'Non', price: 5000, description: '', kind: 'product', status: 'active', businessId: 'bX' });
  await items.doc('p_plain').set({ ownerPhone: OWNER, title: 'Oddiy vitrina', price: 100, kind: 'product', status: 'active' });

  await check('M1 admin mahsulot: faqat admin; sabab shart; mijoz rad', async () => {
    await assert.rejects(call('adminUpdateBusinessProduct', { itemId: 'p_biz', title: 'Hack', reason: 'tuzatish' }, OWNER));
    await assert.rejects(call('adminDeleteBusinessProduct', { itemId: 'p_biz', reason: 'tuzatish' }, OWNER));
    await expectCode(call('adminUpdateBusinessProduct', { itemId: 'p_biz', title: 'Nonn', reason: 'x' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminDeleteBusinessProduct', { itemId: 'p_biz', reason: '' }, ADMIN), 'REASON_REQUIRED');
    assert.strictEqual((await items.doc('p_biz').get()).data().title, 'Non', 'rad etilgan chaqiruv hech narsani o\'zgartirmagan');
  });

  await check('M2 admin tahrirlaydi: faqat berilgan maydonlar, audit changedKeys+reason; o\'zgarishsiz — audit yo\'q', async () => {
    const r = await call('adminUpdateBusinessProduct', { itemId: 'p_biz', title: 'Non (issiq)', price: 6000, reason: 'imlo' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.changedKeys.sort()], [true, ['price', 'title']]);
    const d = (await items.doc('p_biz').get()).data();
    assert.deepStrictEqual([d.title, d.price, d.ownerPhone, d.businessId, d.status], ['Non (issiq)', 6000, OWNER, 'bX', 'active']);
    assert.ok(d.updatedBy === ADMIN || d.updatedBy);
    const a = await auditOf('business_product_update', 'p_biz');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].reason, 'imlo');
    assert.deepStrictEqual(a[0].changedKeys.sort(), ['price', 'title']);
    const again = await call('adminUpdateBusinessProduct', { itemId: 'p_biz', title: 'Non (issiq)', price: 6000, reason: 'imlo' }, ADMIN);
    assert.strictEqual(again.changed, false);
    assert.strictEqual((await auditOf('business_product_update', 'p_biz')).length, 1, 'takror — audit ortmaydi (21-band)');
  });

  await check('M3 tekshiruv: sarlavha/narx/tur/holat chegaralari; hech narsa berilmasa — rad', async () => {
    const code = async (over) => { try { await call('adminUpdateBusinessProduct', { itemId: 'p_biz', reason: 'sinov', ...over }, ADMIN); return 'OK'; } catch (e) { return (e.details && e.details.code) || e.message; } };
    assert.strictEqual(await code({ title: 'A' }), 'PRODUCT_TITLE_INVALID');
    assert.strictEqual(await code({ title: 'x'.repeat(121) }), 'PRODUCT_TITLE_INVALID');
    assert.strictEqual(await code({ price: -1 }), 'PRODUCT_PRICE_INVALID');
    assert.strictEqual(await code({ price: 12.5 }), 'PRODUCT_PRICE_INVALID'); // pul butun (8-band)
    assert.strictEqual(await code({ price: '5000' }), 'PRODUCT_PRICE_INVALID');
    assert.strictEqual(await code({ kind: 'weapon' }), 'PRODUCT_KIND_INVALID');
    assert.strictEqual(await code({ status: 'deleted' }), 'PRODUCT_STATUS_INVALID'); // o'chirish — alohida callable
    assert.strictEqual(await code({ status: 'pending' }), 'PRODUCT_STATUS_INVALID');
    assert.strictEqual(await code({ description: 'x'.repeat(1001) }), 'PRODUCT_FIELD_INVALID');
    assert.strictEqual(await code({}), 'PRODUCT_NOTHING_TO_UPDATE');
    assert.strictEqual(await code({ title: 'x'.repeat(120) }), 'OK'); // chegara: aynan max
    assert.strictEqual(await code({ price: 0 }), 'OK');
  });

  await check('M4 admin blokla/ochadi (status active<->blocked)', async () => {
    await call('adminUpdateBusinessProduct', { itemId: 'p_biz', status: 'blocked', reason: 'qoida buzilgan' }, ADMIN);
    assert.strictEqual((await items.doc('p_biz').get()).data().status, 'blocked');
    await call('adminUpdateBusinessProduct', { itemId: 'p_biz', status: 'active', reason: 'xato bloklangan' }, ADMIN);
    assert.strictEqual((await items.doc('p_biz').get()).data().status, 'active');
  });

  await check('M5 oddiy vitrina hujjatiga (businessId yo\'q) bu yo\'l bilan tegib bo\'lmaydi; yo\'q hujjat — rad', async () => {
    await expectCode(call('adminUpdateBusinessProduct', { itemId: 'p_plain', title: 'Hack', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
    await expectCode(call('adminDeleteBusinessProduct', { itemId: 'p_plain', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
    await expectCode(call('adminDeleteBusinessProduct', { itemId: 'yoq_hujjat', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
    await expectCode(call('adminDeleteBusinessProduct', { itemId: '../x', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
    assert.strictEqual((await items.doc('p_plain').get()).data().title, 'Oddiy vitrina');
  });

  await check('M6 admin o\'chiradi: yumshoq (status deleted), audit snapshot bilan; takror — deleted:false, audit ortmaydi; o\'chirilganni tahrirlab bo\'lmaydi', async () => {
    const r = await call('adminDeleteBusinessProduct', { itemId: 'p_biz', reason: 'soxta mahsulot' }, ADMIN);
    assert.strictEqual(r.deleted, true);
    const d = (await items.doc('p_biz').get()).data();
    assert.strictEqual(d.status, 'deleted');
    assert.strictEqual(d.businessId, 'bX', 'hujjat saqlanadi — tiklash/tekshirish mumkin');
    const a = await auditOf('business_product_delete', 'p_biz');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].reason, 'soxta mahsulot');
    assert.strictEqual(a[0].snapshot.ownerPhone, OWNER);
    const again = await call('adminDeleteBusinessProduct', { itemId: 'p_biz', reason: 'soxta mahsulot' }, ADMIN);
    assert.strictEqual(again.deleted, false);
    assert.strictEqual((await auditOf('business_product_delete', 'p_biz')).length, 1);
    await expectCode(call('adminUpdateBusinessProduct', { itemId: 'p_biz', title: 'Qayta', reason: 'sinov' }, ADMIN), 'PRODUCT_DELETED');
  });

  // ───────── Каскад: объект ўчирилганда маҳсулотлар юмшоқ ўчади ─────────
  const { cascadeBusinessProducts } = require('../business_directory');
  const status = async (id) => (await items.doc(id).get()).data().status;

  await check('K1 cascade: faqat egasining faol mahsulotlari o\'chadi; begona egaga va "admin"ga tegilmaydi; 400 dan ko\'p ham (sahifalash)', async () => {
    const OWNER_PHONE = '998913000001';
    const ALIEN = '998913000002';
    await items.doc('k_mine1').set({ ownerPhone: OWNER_PHONE, title: 'A', status: 'active', businessId: 'kBiz' });
    await items.doc('k_mine2').set({ ownerPhone: '+998 91 300-00-01', title: 'B', status: 'pending', businessId: 'kBiz' });
    await items.doc('k_gone').set({ ownerPhone: OWNER_PHONE, title: 'C', status: 'deleted', businessId: 'kBiz', deletedBy: 'seller' });
    await items.doc('k_alien').set({ ownerPhone: ALIEN, title: 'Spoof', status: 'active', businessId: 'kBiz' });
    await items.doc('k_other_biz').set({ ownerPhone: OWNER_PHONE, title: 'Boshqa obyekt', status: 'active', businessId: 'kOther' });
    await items.doc('k_plain').set({ ownerPhone: OWNER_PHONE, title: 'Oddiy vitrina', status: 'active' });
    // 400 dan ko'p: ikkinchi sahifa ham qamrab olinishi shart
    const bulk = db.batch();
    for (let i = 0; i < 430; i += 1) bulk.set(items.doc(`k_bulk_${String(i).padStart(3, '0')}`), { ownerPhone: OWNER_PHONE, title: `P${i}`, status: 'active', businessId: 'kBiz' });
    await bulk.commit();

    const r = await cascadeBusinessProducts(db, admin, 'kBiz', OWNER_PHONE);
    assert.strictEqual(r.updated, 432, '2 ta oddiy + 430 ta bulk; allaqachon o\'chgan va begona sanalmaydi');
    assert.strictEqual(await status('k_mine1'), 'deleted');
    assert.strictEqual(await status('k_mine2'), 'deleted');
    assert.strictEqual((await items.doc('k_gone').get()).data().deletedBy, 'seller', 'oldin o\'chirilganga qayta yozilmaydi');
    assert.strictEqual(await status('k_alien'), 'active', 'begona eganing "spoof" hujjatiga tegilmaydi');
    assert.strictEqual(await status('k_other_biz'), 'active');
    assert.strictEqual(await status('k_plain'), 'active');
    assert.strictEqual(await status('k_bulk_429'), 'deleted', 'oxirgi sahifa ham');
    const d = (await items.doc('k_mine1').get()).data();
    assert.strictEqual(d.deletedBy, 'system:business_deleted');
    assert.ok(d.deletedAt && d.updatedAt);
  });

  await check('K2 cascade idempotent: ikkinchi chaqiruv — 0 yangilanish; egasiz ("admin") obyekt — hech narsa', async () => {
    const again = await cascadeBusinessProducts(db, admin, 'kBiz', '998913000001');
    assert.strictEqual(again.updated, 0);
    await items.doc('k_adm').set({ ownerPhone: '998913000001', title: 'X', status: 'active', businessId: 'admin_x' });
    const adm = await cascadeBusinessProducts(db, admin, 'admin_x', 'admin');
    assert.deepStrictEqual(adm, { scanned: 0, updated: 0 });
    assert.strictEqual(await status('k_adm'), 'active');
    const none = await cascadeBusinessProducts(db, admin, '', '998913000001');
    assert.strictEqual(none.updated, 0);
  });

  await check('K3 trigger: egasi o\'chirsa ham, admin o\'chirsa ham hujjat o\'chgach mahsulotlar o\'chadi (trigger ishlaydi)', async () => {
    const OWN = '998913000009';
    const ownerBiz = await call('upsertMyBusiness', { ...BASE, clientRequestId: 'casc-00000001' }, OWN);
    await items.doc('k_t1').set({ ownerPhone: OWN, title: 'T1', status: 'active', businessId: ownerBiz.businessId });
    await call('deleteMyBusiness', { businessId: ownerBiz.businessId }, OWN);
    const snapLike = { data: () => ({ ownerId: OWN }) };
    await fns.businessProductsCascade.run(snapLike, { params: { businessId: ownerBiz.businessId } });
    assert.strictEqual(await status('k_t1'), 'deleted');

    const admBiz = await call('adminCreateBusiness', { ...BASE, clientRequestId: 'casc-00000002', ownerPhone: OWN, reason: 'sinov' }, ADMIN);
    await items.doc('k_t2').set({ ownerPhone: OWN, title: 'T2', status: 'active', businessId: admBiz.businessId });
    await call('adminDeleteBusiness', { businessId: admBiz.businessId, reason: 'sinov' }, ADMIN);
    await fns.businessProductsCascade.run({ data: () => ({ ownerId: OWN }) }, { params: { businessId: admBiz.businessId } });
    assert.strictEqual(await status('k_t2'), 'deleted');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
