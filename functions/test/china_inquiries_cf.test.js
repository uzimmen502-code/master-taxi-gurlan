/**
 * XITOY BOZORI «So'rov qoldirish» — callable'lar, HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-china-cf \
 *     "node test/china_inquiries_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-china-cf';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { canTransition, stageAllows, TRANSITIONS } = require('../china_inquiries');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001';
const USER2 = '998912000002';
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
const inquiry = async (id) => (await db.collection('china_inquiries').doc(id).get()).data();
const TEXT = 'Elektr samokat, yengil, 500 dona kerak';

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(USER).set({ role: 'user', appLang: 'uz_Latn' });
  await db.collection('users').doc(USER2).set({ role: 'user' });

  await check('P1 state machine: terminal holatdan chiqish yo\'q; new -> quoted to\'g\'ridan-to\'g\'ri yo\'q', () => {
    assert.ok(canTransition('new', 'sent'));
    assert.ok(!canTransition('new', 'quoted'));
    assert.ok(!canTransition('closed', 'sent'));
    assert.ok(!canTransition('cancelled', 'quoted'));
    assert.ok(!canTransition('bogus', 'sent'));
    assert.deepStrictEqual(TRANSITIONS.closed, []);
    assert.ok(!stageAllows({ stage: 'off' }, USER));
    assert.ok(!stageAllows({ stage: 'internal', testerIds: [USER2] }, USER));
    assert.ok(stageAllows({ stage: 'internal', testerIds: [USER] }, USER));
    assert.ok(stageAllows({ stage: 'public' }, USER));
    assert.ok(!stageAllows({}, USER));
  });

  await check('C1 config yo\'q (OFF): mijoz yarata olmaydi, access=false', async () => {
    assert.deepStrictEqual(await call('getChinaInquiryAccess', {}, USER), { enabled: false });
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: 'req-00000001' }, USER), 'CHINA_INQUIRY_DISABLED');
  });

  await check('C2 config: faqat admin; sabab shart; internal+testerIds; takror — versiya oshmaydi', async () => {
    await assert.rejects(call('adminSetChinaInquiryConfig', { stage: 'internal', reason: 'sinov' }, USER));
    await expectCode(call('adminSetChinaInquiryConfig', { stage: 'internal', reason: '' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminSetChinaInquiryConfig', { stage: 'pilot', reason: 'sinov' }, ADMIN), 'STAGE_INVALID');
    await expectCode(call('adminSetChinaInquiryConfig', { testerIds: ['123'], reason: 'sinov' }, ADMIN), 'TESTERS_INVALID');
    const r = await call('adminSetChinaInquiryConfig', { stage: 'internal', testerIds: [USER], reason: 'ichki sinov' }, ADMIN);
    assert.deepStrictEqual([r.version, r.changed], [1, true]);
    const again = await call('adminSetChinaInquiryConfig', { stage: 'internal', testerIds: [USER], reason: 'qayta' }, ADMIN);
    assert.deepStrictEqual([again.version, again.changed], [1, false]);
    assert.ok((await db.collection('china_inquiry_config_history').doc('v1').get()).exists);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'china_inquiry_config_set').get()).size, 1);
  });

  await check('C3 internal: tester ko\'radi, boshqa foydalanuvchi — yo\'q', async () => {
    assert.deepStrictEqual(await call('getChinaInquiryAccess', {}, USER), { enabled: true });
    assert.deepStrictEqual(await call('getChinaInquiryAccess', {}, USER2), { enabled: false });
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: 'req-00000001' }, USER2), 'CHINA_INQUIRY_DISABLED');
  });

  let inqId; let refNo;
  await check('I1 yaratish: rozilik shart, matn chegarasi, requestId shart; muvaffaqiyatda CN-0001', async () => {
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: false, clientRequestId: 'req-00000001' }, USER), 'CONSENT_REQUIRED');
    await expectCode(call('createChinaInquiry', { text: 'qisqa', consent: true, clientRequestId: 'req-00000001' }, USER), 'TEXT_INVALID');
    await expectCode(call('createChinaInquiry', { text: 'x'.repeat(501), consent: true, clientRequestId: 'req-00000001' }, USER), 'TEXT_INVALID');
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: 'x' }, USER), 'REQUEST_ID_INVALID');
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, quantity: 'q'.repeat(61), clientRequestId: 'req-00000001' }, USER), 'QUANTITY_INVALID');
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, productId: 'no_such', clientRequestId: 'req-00000001' }, USER), 'PRODUCT_INVALID');
    const r = await call('createChinaInquiry', { text: TEXT, quantity: '500 dona', consent: true, clientRequestId: 'req-00000001' }, USER);
    assert.deepStrictEqual([r.ok, r.duplicate, r.refNo], [true, false, 'CN-0001']);
    inqId = r.inquiryId; refNo = r.refNo;
    const d = await inquiry(inqId);
    assert.deepStrictEqual([d.ownerId, d.status, d.quoteCount, d.consentVersion], [USER, 'new', 0, 1]);
    assert.strictEqual(d.textZh, '');
    assert.strictEqual((await db.collection('china_inquiries').doc(inqId).collection('events').get()).size, 1);
  });

  await check('I2 takroriy clientRequestId: dublikat, yangi hujjat va yangi raqam YO\'Q', async () => {
    const r = await call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: 'req-00000001' }, USER);
    assert.deepStrictEqual([r.duplicate, r.inquiryId, r.refNo], [true, inqId, refNo]);
    assert.strictEqual((await db.collection('china_inquiries').get()).size, 1);
    assert.strictEqual((await db.collection('china_inquiry_meta').doc('counter').get()).data().n, 1);
  });

  await check('I3 mahsulot: faqat market=china mahsulot qabul qilinadi', async () => {
    await db.collection('wholesale_products').doc('p_china').set({ market: 'china', title: 'x' });
    await db.collection('wholesale_products').doc('p_local').set({ market: 'wholesale', title: 'y' });
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, productId: 'p_local', clientRequestId: 'req-00000002' }, USER), 'PRODUCT_INVALID');
    const r = await call('createChinaInquiry', { text: TEXT, consent: true, productId: 'p_china', clientRequestId: 'req-00000002' }, USER);
    assert.strictEqual(r.refNo, 'CN-0002');
    assert.strictEqual((await inquiry(r.inquiryId)).productId, 'p_china');
    await call('cancelChinaInquiry', { inquiryId: r.inquiryId }, USER);
  });

  await check('I4 ochiq so\'rovlar chegarasi (5): oltinchi rad; bekor qilingani hisoblanmaydi', async () => {
    // hozir: 1 ochiq (inqId) + 1 bekor. Yana 4 ochiq -> jami 5.
    for (let i = 3; i <= 6; i++) {
      await call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: `req-0000000${i}` }, USER);
    }
    await expectCode(call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: 'req-00000007' }, USER), 'TOO_MANY_OPEN');
    // boshqa foydalanuvchi chegarasi alohida
    await db.collection('china_inquiry_config').doc('main').update({ testerIds: [USER, USER2] });
    const r = await call('createChinaInquiry', { text: TEXT, consent: true, clientRequestId: 'req-00000008' }, USER2);
    assert.ok(r.ok);
  });

  const SUP = {};
  await check('S1 ta\'minotchi: faqat admin; yaratish/tahrirlash; o\'zgarishsiz takror — audit yo\'q', async () => {
    await assert.rejects(call('adminUpsertChinaSupplier', { displayName: 'Li' }, USER));
    await expectCode(call('adminUpsertChinaSupplier', { displayName: 'L' }, ADMIN), 'SUPPLIER_NAME_INVALID');
    const a = await call('adminUpsertChinaSupplier', { displayName: 'Li Electronics', wechatId: 'li_001' }, ADMIN);
    SUP.li = a.supplierId;
    const b = await call('adminUpsertChinaSupplier', { displayName: 'Wang Toys' }, ADMIN);
    SUP.wang = b.supplierId;
    const same = await call('adminUpsertChinaSupplier', { supplierId: SUP.li, displayName: 'Li Electronics', wechatId: 'li_001' }, ADMIN);
    assert.strictEqual(same.changed, false);
    await expectCode(call('adminUpsertChinaSupplier', { supplierId: 'nope', displayName: 'Zed' }, ADMIN), 'SUPPLIER_NOT_FOUND');
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'china_supplier_create').get()).size, 2);
  });

  await check('D1 yuborish: matn tayyor bo\'lmaguncha rad; keyin new->sent; takror bosish dublikat', async () => {
    await expectCode(call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.li }, ADMIN), 'TEXT_ZH_REQUIRED');
    await expectCode(call('adminSetChinaInquiryTextZh', { inquiryId: inqId, textZh: '' }, ADMIN), 'TEXT_ZH_REQUIRED');
    await call('adminSetChinaInquiryTextZh', { inquiryId: inqId, textZh: '我们需要电动滑板车，500台' }, ADMIN);
    await expectCode(call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: 'nope' }, ADMIN), 'SUPPLIER_NOT_FOUND');
    const r = await call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.li }, ADMIN);
    assert.strictEqual(r.duplicate, false);
    assert.strictEqual((await inquiry(inqId)).status, 'sent');
    const again = await call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.li }, ADMIN);
    assert.strictEqual(again.duplicate, true);
    const disp = await db.collection('china_inquiries').doc(inqId).collection('dispatches').get();
    assert.strictEqual(disp.size, 1);
    assert.strictEqual(disp.docs[0].data().textZh, '我们需要电动滑板车，500台');
    const sentEvents = (await db.collection('china_inquiries').doc(inqId).collection('events').where('type', '==', 'sent').get()).size;
    assert.strictEqual(sentEvents, 1, 'takror event yozmaydi');
  });

  await check('D2 nofaol ta\'minotchiga yuborib bo\'lmaydi; oddiy foydalanuvchi admin callable\'ni chaqira olmaydi', async () => {
    await call('adminUpsertChinaSupplier', { supplierId: SUP.wang, displayName: 'Wang Toys', active: false }, ADMIN);
    await expectCode(call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.wang }, ADMIN), 'SUPPLIER_INACTIVE');
    await assert.rejects(call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.li }, USER));
    await assert.rejects(call('adminAddChinaQuote', { inquiryId: inqId, supplierId: SUP.li, priceMinor: 100, currency: 'USD', clientRequestId: 'quote-00001' }, USER));
  });

  const quote = (over = {}) => ({
    inquiryId: inqId, supplierId: SUP.li, priceMinor: 3800, currency: 'USD', minOrderQty: 100, leadTimeDays: 20,
    customerNote: 'Narx FOB', internalNote: 'Li: kredit yo\'q', clientRequestId: 'quote-00001', ...over,
  });
  let quoteId;
  await check('Q1 taklif: validatsiya (butun narx, valyuta, yuborilmagan ta\'minotchi)', async () => {
    await expectCode(call('adminAddChinaQuote', quote({ priceMinor: 38.5 }), ADMIN), 'PRICE_INVALID');
    await expectCode(call('adminAddChinaQuote', quote({ priceMinor: 0 }), ADMIN), 'PRICE_INVALID');
    await expectCode(call('adminAddChinaQuote', quote({ priceMinor: '3800' }), ADMIN), 'PRICE_INVALID');
    await expectCode(call('adminAddChinaQuote', quote({ currency: 'UZS' }), ADMIN), 'CURRENCY_INVALID');
    await expectCode(call('adminAddChinaQuote', quote({ minOrderQty: 0 }), ADMIN), 'MOQ_INVALID');
    await expectCode(call('adminAddChinaQuote', quote({ supplierId: SUP.wang }), ADMIN), 'NOT_DISPATCHED');
    await expectCode(call('adminAddChinaQuote', quote({ clientRequestId: 'x' }), ADMIN), 'REQUEST_ID_INVALID');
  });

  await check('Q2 taklif: sent->quoted, mijozga ta\'minotchisiz nusxa, xabar yoziladi; takror — dublikat', async () => {
    const r = await call('adminAddChinaQuote', quote(), ADMIN);
    assert.strictEqual(r.duplicate, false);
    quoteId = r.quoteId;
    const d = await inquiry(inqId);
    assert.deepStrictEqual([d.status, d.quoteCount], ['quoted', 1]);
    const ref = db.collection('china_inquiries').doc(inqId);
    const offer = (await ref.collection('offers').doc(quoteId).get()).data();
    assert.strictEqual(offer.priceMinor, 3800);
    assert.ok(!('supplierId' in offer) && !('supplierName' in offer) && !('internalNote' in offer), 'offer ta\'minotchi/ichki izohni oshkor qilmasin');
    const internal = (await ref.collection('quotes').doc(quoteId).get()).data();
    assert.deepStrictEqual([internal.supplierId, internal.internalNote], [SUP.li, 'Li: kredit yo\'q']);
    const news = await db.collection('admin_news').where('targetUserId', '==', USER).where('source', '==', 'china_inquiry').get();
    assert.strictEqual(news.size, 1);
    assert.ok(/Xitoy/.test(news.docs[0].data().title), 'uz_Latn matn');
    const nd = news.docs[0].data();
    assert.ok(!/998\d{9}/.test(`${nd.title} ${nd.body}`), 'xabar matnida telefon yo\'q');
    assert.ok(!/Li|Wang/.test(`${nd.title} ${nd.body}`), 'xabarda ta\'minotchi nomi yo\'q');
    const again = await call('adminAddChinaQuote', quote(), ADMIN);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual((await inquiry(inqId)).quoteCount, 1, 'takror hisoblagichni oshirmaydi');
    assert.strictEqual((await db.collection('admin_news').where('targetUserId', '==', USER).where('source', '==', 'china_inquiry').get()).size, 1, 'takror xabar yubormaydi');
  });

  await check('Q3 taklifni qaytarib olish: audit sabab bilan; takror — o\'zgarishsiz', async () => {
    await expectCode(call('adminWithdrawChinaQuote', { inquiryId: inqId, quoteId, reason: '' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminWithdrawChinaQuote', { inquiryId: inqId, quoteId: 'nope', reason: 'xato kiritilgan' }, ADMIN), 'QUOTE_NOT_FOUND');
    const r = await call('adminWithdrawChinaQuote', { inquiryId: inqId, quoteId, reason: 'xato kiritilgan' }, ADMIN);
    assert.strictEqual(r.changed, true);
    const ref = db.collection('china_inquiries').doc(inqId);
    assert.strictEqual((await ref.collection('offers').doc(quoteId).get()).data().withdrawn, true);
    assert.strictEqual((await ref.collection('quotes').doc(quoteId).get()).data().withdrawn, true);
    assert.strictEqual((await call('adminWithdrawChinaQuote', { inquiryId: inqId, quoteId, reason: 'takror' }, ADMIN)).changed, false);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'china_quote_withdraw').get()).size, 1);
  });

  await check('X1 bekor/yopish: begona egasi bekor qila olmaydi; yopilgach hamma amal rad; takror yopish — o\'zgarishsiz', async () => {
    await assert.rejects(call('cancelChinaInquiry', { inquiryId: inqId }, USER2));
    await expectCode(call('adminCloseChinaInquiry', { inquiryId: inqId, reason: '' }, ADMIN), 'REASON_REQUIRED');
    const r = await call('adminCloseChinaInquiry', { inquiryId: inqId, reason: 'mijoz rad etdi' }, ADMIN);
    assert.strictEqual(r.changed, true);
    assert.strictEqual((await call('adminCloseChinaInquiry', { inquiryId: inqId, reason: 'takror' }, ADMIN)).changed, false);
    await expectCode(call('cancelChinaInquiry', { inquiryId: inqId }, USER), 'INVALID_TRANSITION');
    await expectCode(call('adminAddChinaQuote', quote({ clientRequestId: 'quote-00002' }), ADMIN), 'INVALID_TRANSITION');
    // Avval yuborilgan ta'minotchiga takror — idempotent (dublikat); yangi ta'minotchiga — yopilgan so'rovda rad.
    assert.strictEqual((await call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.li }, ADMIN)).duplicate, true);
    await call('adminUpsertChinaSupplier', { supplierId: SUP.wang, displayName: 'Wang Toys', active: true }, ADMIN);
    await expectCode(call('adminMarkChinaInquirySent', { inquiryId: inqId, supplierId: SUP.wang }, ADMIN), 'INVALID_TRANSITION');
    await expectCode(call('adminSetChinaInquiryTextZh', { inquiryId: inqId, textZh: 'x' }, ADMIN), 'INVALID_TRANSITION');
  });

  await check('X2 mijoz bekor qiladi (new holatdan); takror — o\'zgarishsiz; ochiq so\'rovlar soni kamayadi', async () => {
    const list = await db.collection('china_inquiries').where('ownerId', '==', USER).where('status', '==', 'new').limit(1).get();
    const id = list.docs[0].id;
    assert.strictEqual((await call('cancelChinaInquiry', { inquiryId: id }, USER)).changed, true);
    assert.strictEqual((await call('cancelChinaInquiry', { inquiryId: id }, USER)).changed, false);
    assert.strictEqual((await inquiry(id)).status, 'cancelled');
    await expectCode(call('cancelChinaInquiry', { inquiryId: 'no_such_inquiry' }, USER), 'INQUIRY_NOT_FOUND');
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
