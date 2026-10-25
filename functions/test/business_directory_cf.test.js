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

  // 2026-10-25 (ega: «админ назорати барча кириш йўлларида»): ягона омбор — Aholi bozorining yangi mahsulotlari
  // businessId'siz; admin ularni ham bloklay/tahrirlay/o'chira olishi SHART (avval PRODUCT_NOT_FOUND edi).
  await check('M5 oddiy (businessId\'siz) mahsulot: admin tahrirlaydi/bloklaydi/ochadi, audit businessId=\'\'; yo\'q hujjat — rad', async () => {
    const r = await call('adminUpdateBusinessProduct', { itemId: 'p_plain', title: 'Oddiy vitrina (tuzatildi)', reason: 'imlo' }, ADMIN);
    assert.strictEqual(r.changed, true);
    await call('adminUpdateBusinessProduct', { itemId: 'p_plain', status: 'blocked', reason: 'qoida buzilgan' }, ADMIN);
    assert.strictEqual((await items.doc('p_plain').get()).data().status, 'blocked');
    await call('adminUpdateBusinessProduct', { itemId: 'p_plain', status: 'active', reason: 'tekshirildi' }, ADMIN);
    const d = (await items.doc('p_plain').get()).data();
    assert.deepStrictEqual([d.status, d.title], ['active', 'Oddiy vitrina (tuzatildi)']);
    const a = await auditOf('business_product_update', 'p_plain');
    assert.strictEqual(a.length, 3);
    assert.ok(a.every((x) => x.businessId === ''));
    await expectCode(call('adminDeleteBusinessProduct', { itemId: 'yoq_hujjat', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
    await expectCode(call('adminDeleteBusinessProduct', { itemId: '../x', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
    await expectCode(call('adminUpdateBusinessProduct', { itemId: 'yoq_hujjat', title: 'Hack', reason: 'sinov' }, ADMIN), 'PRODUCT_NOT_FOUND');
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

  // ───────── Блоклаш: йўналиш дўкони ва бутун онлайн дўкон (эга қарори 2026-10-25) ─────────
  const SELLER = '998914000001';
  const ALIEN2 = '998914000002';
  const shopDoc = async () => (await db.collection('tv_shops').doc(SELLER).get()).data();
  const item = async (id) => (await items.doc(id).get()).data();
  const inCell = async (cell) => (await db.collection('businesses').where('geohash4', 'in', [cell]).get()).docs.map((d) => d.id);
  const CELL = encode(BASE.lat, BASE.lng, 4);
  const b1 = (await call('upsertMyBusiness', { ...BASE, name: 'Sidabilla Kiyim', clientRequestId: 'blk-00000001' }, SELLER)).businessId;
  const b2 = (await call('upsertMyBusiness', { ...BASE, name: 'Sidabilla Texnika', clientRequestId: 'blk-00000002' }, SELLER)).businessId;
  const seed = db.batch();
  seed.set(items.doc('s_own'), { ownerPhone: SELLER, title: 'O\'z do\'kon', status: 'active' });
  seed.set(items.doc('s_own9'), { ownerPhone: SELLER.slice(3), title: '9 xonali egasi', status: 'active' });
  seed.set(items.doc('s_b1a'), { ownerPhone: SELLER, title: 'Ko\'ylak', status: 'active', businessId: b1 });
  seed.set(items.doc('s_b1p'), { ownerPhone: SELLER, title: 'Kutilmoqda', status: 'pending', businessId: b1 });
  seed.set(items.doc('s_b1x'), { ownerPhone: SELLER, title: 'Admin bloklagan', status: 'blocked', businessId: b1 });
  seed.set(items.doc('s_b1alien'), { ownerPhone: ALIEN2, title: 'Spoof', status: 'active', businessId: b1 });
  seed.set(items.doc('s_b2'), { ownerPhone: SELLER, title: 'Televizor', status: 'active', businessId: b2 });
  await seed.commit();

  await check('B1 adminSetBusinessStatus: faqat admin; sabab, holat, mavjud obyekt shart', async () => {
    await assert.rejects(call('adminSetBusinessStatus', { businessId: b1, status: 'blocked', reason: 'sinov' }, SELLER));
    await expectCode(call('adminSetBusinessStatus', { businessId: b1, status: 'blocked', reason: '' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminSetBusinessStatus', { businessId: b1, status: 'hidden', reason: 'sinov' }, ADMIN), 'BUSINESS_STATUS_INVALID');
    await expectCode(call('adminSetBusinessStatus', { businessId: 'yoq_obyekt', status: 'blocked', reason: 'sinov' }, ADMIN), 'BUSINESS_NOT_FOUND');
    assert.strictEqual((await biz(b1)).status, 'active');
  });

  await check('B2 yo\'nalishni bloklash: xaritadan yo\'qoladi (geohash yo\'q), faqat egasining FAOL mahsulotlari bloklanadi + belgi; audit', async () => {
    assert.ok((await inCell(CELL)).includes(b1));
    const r = await call('adminSetBusinessStatus', { businessId: b1, status: 'blocked', reason: 'soxta do\'kon' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.products], [true, 1]);
    const d = await biz(b1);
    assert.deepStrictEqual([d.status, d.blockReason, d.blockedBy, d.geohash4, d.geohash], ['blocked', 'soxta do\'kon', ADMIN, undefined, undefined]);
    assert.deepStrictEqual([d.lat, d.lng, d.blockedGeo], [undefined, undefined, { lat: BASE.lat, lng: BASE.lng }],
      'koordinatasiz hujjatni eski APK umumiy ko\'rinishda ham chizmaydi (Business.tryFromMap -> null); joyi saqlanadi');
    assert.ok(!(await inCell(CELL)).includes(b1), 'xarita so\'rovi (eski APK ham) uni topmaydi');
    assert.ok((await inCell(CELL)).includes(b2), 'boshqa yo\'nalish ko\'rinib turadi');
    assert.deepStrictEqual([(await item('s_b1a')).status, (await item('s_b1a')).blockedByParent], ['blocked', `business:${b1}`]);
    assert.strictEqual((await item('s_b1p')).status, 'pending');
    assert.strictEqual((await item('s_b1x')).blockedByParent, undefined, 'admin alohida bloklagani belgisiz qoladi');
    assert.strictEqual((await item('s_b1alien')).status, 'active', 'begona "spoof" hujjatga tegilmaydi');
    assert.strictEqual((await item('s_b2')).status, 'active');
    assert.strictEqual((await item('s_own')).status, 'active');
    assert.strictEqual((await auditOf('business_block', b1)).length, 1);
  });

  await check('B3 takror bloklash: changed:false, audit ortmaydi, mahsulotlar qayta yozilmaydi (21-band)', async () => {
    const r = await call('adminSetBusinessStatus', { businessId: b1, status: 'blocked', reason: 'soxta do\'kon' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.products], [false, 0]);
    assert.strictEqual((await auditOf('business_block', b1)).length, 1);
  });

  await check('B4 bloklangan obyekt: egasi tahrirlasa ham xaritaga qaytmaydi; egasi o\'chira olmaydi', async () => {
    const same = await call('upsertMyBusiness', { ...BASE, businessId: b1, name: 'Sidabilla Kiyim' }, SELLER);
    assert.strictEqual(same.changed, false, 'blokda ham o\'zgarishsiz tahrir — changed:false (joy blockedGeo\'dan solishtiriladi)');
    const e = await call('upsertMyBusiness', { ...BASE, businessId: b1, name: 'Yangi nom', lat: 41.3, lng: 69.2 }, SELLER);
    assert.strictEqual(e.changed, true);
    const d = await biz(b1);
    assert.deepStrictEqual([d.name, d.status, d.geohash4, d.lat, d.blockedGeo], ['Yangi nom', 'blocked', undefined, undefined, { lat: 41.3, lng: 69.2 }]);
    const a = await call('adminUpdateBusiness', { ...BASE, businessId: b1, name: 'Admin nomi', lat: 41.3, lng: 69.2, reason: 'imlo' }, ADMIN);
    assert.strictEqual(a.changed, true);
    assert.deepStrictEqual([(await biz(b1)).lat, (await biz(b1)).geohash4], [undefined, undefined], 'admin tahriri ham xaritaga qaytarmaydi');
    await expectCode(call('deleteMyBusiness', { businessId: b1 }, SELLER), 'BUSINESS_BLOCKED');
    assert.ok(await biz(b1));
  });

  await check('B5 mahsulotni ochish: yo\'nalishi bloklangan bo\'lsa — PARENT_BLOCKED; admin alohida bloklasa belgi olinadi', async () => {
    await expectCode(call('adminUpdateBusinessProduct', { itemId: 's_b1a', status: 'active', reason: 'sinov' }, ADMIN), 'PARENT_BLOCKED');
    assert.strictEqual((await item('s_b1a')).status, 'blocked');
    await items.doc('s_b1b').set({ ownerPhone: SELLER, title: 'Shim', status: 'blocked', businessId: b1, blockedByParent: `business:${b1}` });
    const r = await call('adminUpdateBusinessProduct', { itemId: 's_b1b', status: 'blocked', reason: 'o\'zi ham buzilgan' }, ADMIN);
    assert.strictEqual(r.changed, true);
    assert.strictEqual((await item('s_b1b')).blockedByParent, undefined);
  });

  await check('B6 yo\'nalishni ochish: geohash koordinatadan qaytadi, faqat shu belgili mahsulotlar ochiladi; audit', async () => {
    const r = await call('adminSetBusinessStatus', { businessId: b1, status: 'active', reason: 'tekshirildi' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.products], [true, 1]);
    const d = await biz(b1);
    assert.deepStrictEqual([d.status, d.geohash4, d.blockReason, d.blockedBy], ['active', encode(41.3, 69.2, 4), undefined, undefined]);
    assert.deepStrictEqual([d.lat, d.lng, d.blockedGeo, d.geohash], [41.3, 69.2, undefined, encode(41.3, 69.2, 9)]);
    assert.deepStrictEqual([(await item('s_b1a')).status, (await item('s_b1a')).blockedByParent], ['active', undefined]);
    assert.strictEqual((await item('s_b1x')).status, 'blocked', 'admin alohida bloklagani qoladi');
    assert.strictEqual((await item('s_b1b')).status, 'blocked', 'alohida bloklangan (belgisi olingan) qoladi');
    assert.strictEqual((await auditOf('business_unblock', b1)).length, 1);
  });

  await check('S1 adminSetShopStatus: faqat admin; telefon, sabab, holat shart; yo\'q do\'konni ochish — SHOP_NOT_FOUND', async () => {
    await assert.rejects(call('adminSetShopStatus', { ownerPhone: SELLER, status: 'blocked', reason: 'sinov' }, SELLER));
    await expectCode(call('adminSetShopStatus', { ownerPhone: '123', status: 'blocked', reason: 'sinov' }, ADMIN), 'SHOP_OWNER_INVALID');
    await expectCode(call('adminSetShopStatus', { ownerPhone: SELLER, status: 'x', reason: 'sinov' }, ADMIN), 'BUSINESS_STATUS_INVALID');
    await expectCode(call('adminSetShopStatus', { ownerPhone: SELLER, status: 'active', reason: 'sinov' }, ADMIN), 'SHOP_NOT_FOUND');
    assert.strictEqual(await shopDoc(), undefined);
  });

  await check('S2 butun do\'konni bloklash: tv_shops yaratiladi (faqat yo\'nalishlari bor egaga ham), barcha yo\'nalish + mahsulot bloklanadi', async () => {
    const r = await call('adminSetShopStatus', { ownerPhone: '+998 91 400-00-01', status: 'blocked', reason: 'firibgarlik' }, ADMIN);
    assert.strictEqual(r.changed, true);
    assert.strictEqual(r.businesses, 2);
    const s = await shopDoc();
    assert.deepStrictEqual([s.status, s.ownerPhone, s.blockReason], ['blocked', SELLER, 'firibgarlik']);
    for (const id of [b1, b2]) {
      const d = await biz(id);
      assert.deepStrictEqual([d.status, d.blockedByParent, d.geohash4, d.lat], ['blocked', 'shop', undefined, undefined]);
      assert.ok(d.blockedGeo && typeof d.blockedGeo.lat === 'number');
    }
    assert.deepStrictEqual([(await item('s_own')).status, (await item('s_own')).blockedByParent], ['blocked', 'shop']);
    assert.strictEqual((await item('s_own9')).status, 'blocked', '9 xonali egasi yozuvi ham');
    assert.strictEqual((await item('s_b2')).blockedByParent, 'shop');
    assert.strictEqual((await item('s_b1x')).blockedByParent, undefined, 'avval bloklangani belgisiz qoladi');
    assert.strictEqual((await item('s_b1alien')).status, 'active', 'begona egasi');
    assert.strictEqual((await auditOf('shop_block', SELLER)).length, 1);
  });

  await check('S3 do\'kon bloklanganda: yangi yo\'nalish ochib bo\'lmaydi, yo\'nalish/mahsulotni alohida ochib bo\'lmaydi', async () => {
    await expectCode(call('upsertMyBusiness', { ...BASE, clientRequestId: 'blk-00000003' }, SELLER), 'SHOP_BLOCKED');
    await expectCode(call('adminSetBusinessStatus', { businessId: b2, status: 'active', reason: 'sinov' }, ADMIN), 'SHOP_BLOCKED');
    await expectCode(call('adminUpdateBusinessProduct', { itemId: 's_own', status: 'active', reason: 'sinov' }, ADMIN), 'PARENT_BLOCKED');
  });

  await check('S4 do\'kon blokida yo\'nalishni admin alohida bloklasa, do\'kon ochilganda o\'sha yo\'nalish va uning mahsuloti bloklangan qoladi', async () => {
    const x = await call('adminSetBusinessStatus', { businessId: b2, status: 'blocked', reason: 'alohida buzilish' }, ADMIN);
    assert.strictEqual(x.changed, true);
    assert.strictEqual((await biz(b2)).blockedByParent, undefined);
    const r = await call('adminSetShopStatus', { ownerPhone: SELLER, status: 'active', reason: 'tekshirildi' }, ADMIN);
    assert.strictEqual(r.changed, true);
    assert.strictEqual((await shopDoc()).status, 'active');
    const d1 = await biz(b1);
    assert.deepStrictEqual([d1.status, d1.geohash4, d1.lat, d1.blockedGeo], ['active', encode(41.3, 69.2, 4), 41.3, undefined]);
    assert.strictEqual((await biz(b2)).status, 'blocked');
    assert.deepStrictEqual((await biz(b2)).blockedGeo, { lat: BASE.lat, lng: BASE.lng }, 'alohida bloklashda joyi yo\'qolmagan');
    assert.deepStrictEqual([(await item('s_own')).status, (await item('s_own')).blockedByParent], ['active', undefined]);
    assert.strictEqual((await item('s_own9')).status, 'active');
    assert.deepStrictEqual([(await item('s_b2')).status, (await item('s_b2')).blockedByParent], ['blocked', `business:${b2}`]);
    assert.strictEqual((await item('s_b1x')).status, 'blocked');
    const y = await call('adminSetBusinessStatus', { businessId: b2, status: 'active', reason: 'tekshirildi' }, ADMIN);
    assert.strictEqual(y.products, 1);
    assert.strictEqual((await item('s_b2')).status, 'active');
  });

  await check('S5 takror ochish: changed:false, kaskad 0, audit ortmaydi', async () => {
    const r = await call('adminSetShopStatus', { ownerPhone: SELLER, status: 'active', reason: 'tekshirildi' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.businesses, r.products], [false, 0, 0]);
    assert.strictEqual((await auditOf('shop_unblock', SELLER)).length, 1);
  });

  // ───────── Харидор шикояти (submitShopComplaint) ─────────
  const BUYER = '998914000009';
  const reportsOf = async (who) => (await db.collection('reports').where('reporterId', '==', who).get()).docs.map((x) => x.data());
  await items.doc('c_item').set({ ownerPhone: SELLER, title: 'Shikoyatli mahsulot', status: 'active', businessId: b1 });
  await items.doc('c_gone').set({ ownerPhone: SELLER, title: 'O\'chgan', status: 'deleted' });

  await check('R1 shikoyat tekshiruvi: tur, sabab, loginsiz, o\'ziga, yo\'q/o\'chgan mahsulot, noto\'g\'ri telefon', async () => {
    await assert.rejects(fns.submitShopComplaint.run({ targetType: 'shop_item', targetId: 'c_item', reason: 'spam' }, {}));
    await expectCode(call('submitShopComplaint', { targetType: 'ad', targetId: 'c_item', reason: 'spam' }, BUYER), 'COMPLAINT_TARGET_INVALID');
    await expectCode(call('submitShopComplaint', { targetType: 'shop_item', targetId: 'c_item', reason: 'x' }, BUYER), 'REASON_REQUIRED');
    await expectCode(call('submitShopComplaint', { targetType: 'shop_item', targetId: 'c_item', reason: 'spam' }, SELLER), 'COMPLAINT_OWN');
    await expectCode(call('submitShopComplaint', { targetType: 'shop', targetId: SELLER, reason: 'spam' }, SELLER), 'COMPLAINT_OWN');
    await expectCode(call('submitShopComplaint', { targetType: 'shop_item', targetId: 'yoq_hujjat', reason: 'spam' }, BUYER), 'PRODUCT_NOT_FOUND');
    await expectCode(call('submitShopComplaint', { targetType: 'shop_item', targetId: 'c_gone', reason: 'spam' }, BUYER), 'PRODUCT_NOT_FOUND');
    await expectCode(call('submitShopComplaint', { targetType: 'shop', targetId: '123', reason: 'spam' }, BUYER), 'SHOP_OWNER_INVALID');
    assert.strictEqual((await reportsOf(BUYER)).length, 0);
  });

  await check('R2 mahsulot shikoyati: reports (shop_content) egasi/yo\'nalishi/nomi bilan; takror — duplicate, yangi hujjat yo\'q', async () => {
    const r = await call('submitShopComplaint', { targetType: 'shop_item', targetId: 'c_item', reason: 'Aldamchi e\'lon' }, BUYER);
    assert.strictEqual(r.ok, true);
    const d = (await db.collection('reports').doc(r.reportId).get()).data();
    assert.deepStrictEqual(
      [d.type, d.targetType, d.targetId, d.ownerPhone, d.businessId, d.title, d.reporterId, d.status],
      ['shop_content', 'shop_item', 'c_item', SELLER, b1, 'Shikoyatli mahsulot', BUYER, 'open'],
    );
    const again = await call('submitShopComplaint', { targetType: 'shop_item', targetId: 'c_item', reason: 'Spam' }, BUYER);
    assert.deepStrictEqual([again.duplicate, again.reportId], [true, r.reportId]);
    assert.strictEqual((await reportsOf(BUYER)).length, 1);
  });

  await check('R3 do\'kon shikoyati telefon bo\'yicha; kunlik chegara (20) — keyingisi COMPLAINT_LIMIT', async () => {
    const r = await call('submitShopComplaint', { targetType: 'shop', targetId: '+998 91 400-00-01', reason: 'Firibgar' }, BUYER);
    assert.strictEqual((await db.collection('reports').doc(r.reportId).get()).data().targetId, SELLER);
    const { COMPLAINT_DAILY_LIMIT } = require('../business_directory');
    for (let i = 2; i < COMPLAINT_DAILY_LIMIT; i += 1) {
      await call('submitShopComplaint', { targetType: 'shop', targetId: `9989150000${String(i).padStart(2, '0')}`, reason: 'spam' }, BUYER);
    }
    assert.strictEqual((await reportsOf(BUYER)).length, COMPLAINT_DAILY_LIMIT);
    await expectCode(call('submitShopComplaint', { targetType: 'shop', targetId: '998915000099', reason: 'spam' }, BUYER), 'COMPLAINT_LIMIT');
  });

  // ───────── Фақат онлайн йўналиш (жисмоний жойи йўқ) ─────────
  const ONL = '998914000020';
  const { lat: _l, lng: _g, ...NOLOC } = BASE; // eslint-disable-line no-unused-vars
  await check('O1 online:true — koordinatasiz yaratiladi; lat/lng/geohash YO\'Q (xaritaga tushmaydi); yuborilgan koordinata e\'tiborsiz', async () => {
    const r = await call('upsertMyBusiness', { ...NOLOC, online: true, clientRequestId: 'onl-00000001' }, ONL);
    const d = await biz(r.businessId);
    assert.deepStrictEqual([d.online, d.lat, d.lng, d.geohash, d.geohash4, d.status], [true, undefined, undefined, undefined, undefined, 'active']);
    const r2 = await call('upsertMyBusiness', { ...BASE, online: true, clientRequestId: 'onl-00000002' }, ONL);
    assert.strictEqual((await biz(r2.businessId)).lat, undefined, 'online — uy manzili nuqta bo\'lib qolmaydi');
    await expectCode(call('upsertMyBusiness', { ...NOLOC, clientRequestId: 'onl-00000003' }, ONL), 'BUSINESS_LOCATION_INVALID');
  });

  await check('O2 online -> jismoniy: koordinata va geohash yoziladi, online o\'chadi; qaytib online: joy maydonlari o\'chadi', async () => {
    const id = `${ONL}_onl-00000001`;
    const same = await call('upsertMyBusiness', { ...NOLOC, online: true, businessId: id }, ONL);
    assert.strictEqual(same.changed, false, 'o\'zgarishsiz');
    await call('upsertMyBusiness', { ...BASE, businessId: id }, ONL);
    let d = await biz(id);
    assert.deepStrictEqual([d.online, d.lat, d.geohash4], [undefined, BASE.lat, encode(BASE.lat, BASE.lng, 4)]);
    await call('upsertMyBusiness', { ...NOLOC, online: true, businessId: id }, ONL);
    d = await biz(id);
    assert.deepStrictEqual([d.online, d.lat, d.lng, d.geohash, d.geohash4], [true, undefined, undefined, undefined, undefined]);
  });

  await check('O3 online yo\'nalish bloklanadi/ochiladi (koordinatasiz ham); blokda online<->jismoniy almashmaydi', async () => {
    const id = `${ONL}_onl-00000001`;
    await call('adminSetBusinessStatus', { businessId: id, status: 'blocked', reason: 'sinov' }, ADMIN);
    let d = await biz(id);
    assert.deepStrictEqual([d.status, d.blockedGeo, d.online], ['blocked', undefined, true]);
    const e = await call('upsertMyBusiness', { ...NOLOC, online: true, businessId: id, name: 'Yangi online' }, ONL);
    assert.strictEqual(e.changed, true);
    await expectCode(call('upsertMyBusiness', { ...BASE, businessId: id }, ONL), 'BUSINESS_BLOCKED');
    await call('adminSetBusinessStatus', { businessId: id, status: 'active', reason: 'sinov' }, ADMIN);
    d = await biz(id);
    assert.deepStrictEqual([d.status, d.lat, d.geohash4, d.online, d.name], ['active', undefined, undefined, true, 'Yangi online']);
  });

  // ───────── Филиаллар (branchOf) ─────────
  const BR = '998914000030';
  const BR2 = '998914000031';
  const main = (await call('upsertMyBusiness', { ...BASE, name: 'Asosiy', clientRequestId: 'brn-00000001' }, BR)).businessId;
  const alienMain = (await call('upsertMyBusiness', { ...BASE, name: 'Begona', clientRequestId: 'brn-00000002' }, BR2)).businessId;
  let branch;
  await check('F1 filial: o\'z yo\'nalishiga — qabul; begona, filialning filiali, o\'zi, online, yo\'q ota — rad; filiali bor obyekt filial bo\'lolmaydi', async () => {
    const r = await call('upsertMyBusiness', { ...BASE, name: 'Filial 1', lat: 41.5, lng: 60.5, branchOf: main, clientRequestId: 'brn-00000003' }, BR);
    branch = r.businessId;
    assert.strictEqual((await biz(branch)).branchOf, main);
    await expectCode(call('upsertMyBusiness', { ...BASE, branchOf: alienMain, clientRequestId: 'brn-00000004' }, BR), 'BRANCH_INVALID');
    await expectCode(call('upsertMyBusiness', { ...BASE, branchOf: branch, clientRequestId: 'brn-00000005' }, BR), 'BRANCH_INVALID');
    await expectCode(call('upsertMyBusiness', { ...BASE, branchOf: 'yoq_obyekt', clientRequestId: 'brn-00000006' }, BR), 'BRANCH_INVALID');
    await expectCode(call('upsertMyBusiness', { ...NOLOC, online: true, branchOf: main, clientRequestId: 'brn-00000007' }, BR), 'BRANCH_INVALID');
    await expectCode(call('upsertMyBusiness', { ...BASE, name: 'Filial 1', branchOf: branch, businessId: branch }, BR), 'BRANCH_INVALID');
    const other = (await call('upsertMyBusiness', { ...BASE, name: 'Boshqa', clientRequestId: 'brn-00000008' }, BR)).businessId;
    await expectCode(call('upsertMyBusiness', { ...BASE, name: 'Asosiy', branchOf: other, businessId: main }, BR), 'BRANCH_NESTED');
    // filiallikdan chiqarish: branchOf o'chadi
    const solo = (await call('upsertMyBusiness', { ...BASE, name: 'Vaqtincha', branchOf: main, clientRequestId: 'brn-00000009' }, BR)).businessId;
    await call('upsertMyBusiness', { ...BASE, name: 'Vaqtincha', businessId: solo }, BR);
    assert.strictEqual((await biz(solo)).branchOf, undefined);
  });

  await check('F2 ota bloklansa filial ham (xaritadan yo\'qoladi); ota blokda filialni alohida ochib bo\'lmaydi; ota ochilsa filial qaytadi', async () => {
    const r = await call('adminSetBusinessStatus', { businessId: main, status: 'blocked', reason: 'sinov' }, ADMIN);
    assert.ok(r.branches >= 1);
    let f = await biz(branch);
    assert.deepStrictEqual([f.status, f.blockedByParent, f.geohash4, f.lat], ['blocked', `business:${main}`, undefined, undefined]);
    await expectCode(call('adminSetBusinessStatus', { businessId: branch, status: 'active', reason: 'sinov' }, ADMIN), 'PARENT_BLOCKED');
    await call('adminSetBusinessStatus', { businessId: main, status: 'active', reason: 'sinov' }, ADMIN);
    f = await biz(branch);
    assert.deepStrictEqual([f.status, f.blockedByParent, f.lat, f.geohash4], ['active', undefined, 41.5, encode(41.5, 60.5, 4)]);
  });

  await check('F3 do\'kon blokida ota alohida bloklansa: do\'kon ochilganda filial ota belgisiga o\'tadi; ota ochilsa qaytadi', async () => {
    await call('adminSetShopStatus', { ownerPhone: BR, status: 'blocked', reason: 'sinov' }, ADMIN);
    assert.strictEqual((await biz(branch)).blockedByParent, 'shop');
    await call('adminSetBusinessStatus', { businessId: main, status: 'blocked', reason: 'alohida' }, ADMIN);
    await call('adminSetShopStatus', { ownerPhone: BR, status: 'active', reason: 'sinov' }, ADMIN);
    let f = await biz(branch);
    assert.deepStrictEqual([f.status, f.blockedByParent], ['blocked', `business:${main}`]);
    await call('adminSetBusinessStatus', { businessId: main, status: 'active', reason: 'sinov' }, ADMIN);
    f = await biz(branch);
    assert.strictEqual(f.status, 'active');
  });

  await check('F4 ota o\'chirilsa filiallar mustaqil yo\'nalish bo\'ladi (branchOf olinadi)', async () => {
    const snapLike = { data: () => ({ ownerId: BR }) };
    await call('deleteMyBusiness', { businessId: main }, BR);
    await fns.businessProductsCascade.run(snapLike, { params: { businessId: main } });
    const f = await biz(branch);
    assert.deepStrictEqual([f.branchOf, f.status], [undefined, 'active']);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
