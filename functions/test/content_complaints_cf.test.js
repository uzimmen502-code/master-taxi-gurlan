/**
 * ХАРИДОР ШИКОЯТИ (ресторан / таом / кўчмас мулк) — `submitContentComplaint`, ҲАҚИҚИЙ `functions/index.js`,
 * Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-content-complaints \
 *     "node test/content_complaints_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-content-complaints';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { parseComplaintInput, REASONS, COMMENT_MAX, DAILY_LIMIT } = require('../content_complaints');

const db = admin.firestore();
const OWNER = '998913000001';
const STAFF = '998913000002';
const BUYER = '998913000003';
const BUYER2 = '998913000004';
const REALTOR = '998913000005';
const TEAMMATE = '998913000006';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (data, who) => fns.submitContentComplaint.run(data, who ? ctxOf(who) : {});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.code || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const reportsOf = async (who) => (await db.collection('reports').where('reporterId', '==', who).get()).docs;
const T = admin.firestore.Timestamp;

async function main() {
  await clearEmulator();
  const r = db.collection('restaurants');
  await r.doc('r_ok').set({ name: 'Gurlan Osh', status: 'approved', ownerUid: OWNER });
  await r.doc('r_ok').collection('members').doc(OWNER).set({ role: 'owner' });
  await r.doc('r_ok').collection('members').doc(STAFF).set({ role: 'staff' });
  await r.doc('r_ok').collection('menu_items').doc('dish1').set({ name: 'Palov', price: 30000 });
  await r.doc('r_ok').collection('menu_items').doc('dish_off').set({ name: 'Manti', price: 20000, available: false });
  await r.doc('r_susp').set({ name: 'Yopiq', status: 'suspended', ownerUid: OWNER });
  await r.doc('r_susp').collection('menu_items').doc('dish2').set({ name: 'Lag\'mon', price: 25000 });
  await r.doc('r_app').set({ name: 'Ariza', status: 'applied', ownerUid: OWNER });
  await db.collection('users').doc(REALTOR).set({ role: 'user', realtyOwnerKey: 'key_realtor' });
  await db.collection('users').doc(TEAMMATE).set({ role: 'user', realtyOwnerKey: 'key_realtor' });
  await db.collection('users').doc(BUYER).set({ role: 'user', realtyOwnerKey: 'key_buyer' });
  const future = T.fromMillis(Date.now() + 86400000);
  const listing = async (id, extra) => {
    await db.collection('realty_listings').doc(id).set({ ownerKey: 'key_realtor', title: 'Uy sotiladi', text: '3 xona', status: 'active', expiresAt: future, ...extra });
    await db.collection('realty_listings').doc(id).collection('private').doc('detail').set({ ownerId: REALTOR, ownerPhone: REALTOR });
  };
  await listing('L_ok', {});
  await listing('L_pending', { status: 'pending' });
  await listing('L_blocked', { status: 'blocked' });
  await listing('L_expired', { expiresAt: T.fromMillis(Date.now() - 1000) });
  await listing('L_nokey', { ownerKey: 'key_other' }); // калит бошқа, лекин private.ownerId — REALTOR

  const fail = (status, code) => Object.assign(new Error(code), { details: { code } });

  await check('P1 parse: sabab faqat ro\'yxatdan; other — izoh 3..300; izoh <= 300; taomga restaurantId shart', () => {
    const code = (d) => { try { parseComplaintInput(d, fail); return 'OK'; } catch (e) { return e.details.code; } };
    const base = { targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud' };
    assert.deepStrictEqual(REASONS, ['fraud', 'wrong_info', 'spam', 'abuse', 'other']);
    assert.strictEqual(code(base), 'OK');
    assert.strictEqual(code({ ...base, reason: 'Алдамчи эълон' }), 'COMPLAINT_REASON_INVALID');
    assert.strictEqual(code({ ...base, reason: undefined }), 'COMPLAINT_REASON_INVALID');
    assert.strictEqual(code({ ...base, reason: 'other' }), 'COMPLAINT_COMMENT_INVALID');
    assert.strictEqual(code({ ...base, reason: 'other', comment: 'ab' }), 'COMPLAINT_COMMENT_INVALID');
    assert.strictEqual(code({ ...base, reason: 'other', comment: 'abc' }), 'OK');
    assert.strictEqual(code({ ...base, comment: 'x'.repeat(COMMENT_MAX) }), 'OK'); // chegara
    assert.strictEqual(code({ ...base, comment: 'x'.repeat(COMMENT_MAX + 1) }), 'COMPLAINT_COMMENT_INVALID');
    assert.strictEqual(code({ ...base, comment: 42 }), 'COMPLAINT_COMMENT_INVALID');
    assert.strictEqual(code({ ...base, targetType: 'shop' }), 'COMPLAINT_TARGET_INVALID');
    assert.strictEqual(code({ ...base, targetId: 'a/b' }), 'COMPLAINT_TARGET_INVALID');
    assert.strictEqual(code({ ...base, targetId: '' }), 'COMPLAINT_TARGET_INVALID');
    assert.strictEqual(code({ targetType: 'restaurant_item', targetId: 'dish1', reason: 'spam' }), 'COMPLAINT_TARGET_INVALID');
    assert.strictEqual(code({ targetType: 'restaurant_item', targetId: 'dish1', restaurantId: 'r_ok', reason: 'spam' }), 'OK');
  });

  await check('N1 loginsiz va telefonsiz token — unauthenticated, hujjat yo\'q', async () => {
    await expectCode(call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud' }), 'unauthenticated');
    await expectCode(fns.submitContentComplaint.run({ targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud' }, { auth: { uid: 'x', token: {} } }), 'unauthenticated');
    assert.strictEqual((await db.collection('reports').get()).size, 0);
  });

  await check('N2 o\'ziga: restoran egasi, xodim (members), taom egasi; realtor, jamoa a\'zosi (ownerKey), private.ownerId', async () => {
    await expectCode(call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud' }, OWNER), 'COMPLAINT_OWN');
    await expectCode(call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud' }, STAFF), 'COMPLAINT_OWN');
    await expectCode(call({ targetType: 'restaurant_item', restaurantId: 'r_ok', targetId: 'dish1', reason: 'spam' }, STAFF), 'COMPLAINT_OWN');
    await expectCode(call({ targetType: 'realty_listing', targetId: 'L_ok', reason: 'fraud' }, REALTOR), 'COMPLAINT_OWN');
    await expectCode(call({ targetType: 'realty_listing', targetId: 'L_ok', reason: 'fraud' }, TEAMMATE), 'COMPLAINT_OWN');
    await expectCode(call({ targetType: 'realty_listing', targetId: 'L_nokey', reason: 'fraud' }, REALTOR), 'COMPLAINT_OWN');
    assert.strictEqual((await db.collection('reports').get()).size, 0);
  });

  await check('N3 ko\'rinmaydigan/yo\'q obyekt — bir xil COMPLAINT_TARGET_NOT_FOUND', async () => {
    const nf = (d) => expectCode(call(d, BUYER), 'COMPLAINT_TARGET_NOT_FOUND');
    await nf({ targetType: 'restaurant', targetId: 'r_susp', reason: 'fraud' });
    await nf({ targetType: 'restaurant', targetId: 'r_app', reason: 'fraud' });
    await nf({ targetType: 'restaurant', targetId: 'yoq', reason: 'fraud' });
    await nf({ targetType: 'restaurant_item', restaurantId: 'r_susp', targetId: 'dish2', reason: 'fraud' });
    await nf({ targetType: 'restaurant_item', restaurantId: 'r_ok', targetId: 'yoq_taom', reason: 'fraud' });
    await nf({ targetType: 'restaurant_item', restaurantId: 'yoq', targetId: 'dish1', reason: 'fraud' });
    for (const id of ['L_pending', 'L_blocked', 'L_expired', 'L_yoq']) await nf({ targetType: 'realty_listing', targetId: id, reason: 'fraud' });
    assert.strictEqual((await db.collection('reports').get()).size, 0);
  });

  await check('N4 noto\'g\'ri sabab / tur / juda uzun izoh — hujjat yo\'q', async () => {
    await expectCode(call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'yomon' }, BUYER), 'COMPLAINT_REASON_INVALID');
    await expectCode(call({ targetType: 'shop_item', targetId: 'r_ok', reason: 'fraud' }, BUYER), 'COMPLAINT_TARGET_INVALID');
    await expectCode(call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud', comment: 'x'.repeat(301) }, BUYER), 'COMPLAINT_COMMENT_INVALID');
    assert.strictEqual((await db.collection('reports').get()).size, 0);
  });

  let restId;
  await check('C1 restoran shikoyati: reports (restaurant_content) minimal shakl; telefon/egasi yozilmaydi', async () => {
    const res = await call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'wrong_info', comment: '  Narx boshqa  ' }, BUYER);
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.duplicate, undefined);
    restId = res.reportId;
    const d = (await db.collection('reports').doc(restId).get()).data();
    assert.ok(d.createdAt && typeof d.createdAt.toMillis === 'function');
    delete d.createdAt;
    assert.deepStrictEqual(d, {
      type: 'restaurant_content', targetType: 'restaurant', targetId: 'r_ok', restaurantId: 'r_ok', title: 'Gurlan Osh',
      reporterId: BUYER, reason: 'wrong_info', comment: 'Narx boshqa', status: 'open',
    });
  });

  await check('C2 takror (ochiq) — duplicate, o\'sha ID, yangi hujjat yo\'q; boshqa obyekt — alohida', async () => {
    const again = await call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'spam' }, BUYER);
    assert.deepStrictEqual(again, { ok: true, reportId: restId, duplicate: true });
    assert.strictEqual((await reportsOf(BUYER)).length, 1);
    const dish = await call({ targetType: 'restaurant_item', restaurantId: 'r_ok', targetId: 'dish1', reason: 'abuse' }, BUYER);
    assert.notStrictEqual(dish.reportId, restId);
    const d = (await db.collection('reports').doc(dish.reportId).get()).data();
    assert.strictEqual(d.targetType, 'restaurant_item');
    assert.strictEqual(d.targetId, 'dish1');
    assert.strictEqual(d.restaurantId, 'r_ok');
    assert.strictEqual(d.title, 'Palov');
    assert.strictEqual(d.comment, '');
    // Ega qarori 2026-10-25: sotuvda bo'lmagan taomga shikoyat YO'Q — available:false va stop-list (stopUntil kelajakda).
    await expectCode(call({ targetType: 'restaurant_item', restaurantId: 'r_ok', targetId: 'dish_off', reason: 'spam' }, BUYER), 'COMPLAINT_TARGET_NOT_FOUND');
    await db.collection('restaurants').doc('r_ok').collection('menu_items').doc('dish_stop').set({
      name: 'Chuchvara', price: 20000, available: true, stopUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000) });
    await expectCode(call({ targetType: 'restaurant_item', restaurantId: 'r_ok', targetId: 'dish_stop', reason: 'spam' }, BUYER), 'COMPLAINT_TARGET_NOT_FOUND');
    // stop muddati o'tgan — yana sotuvda, shikoyat mumkin (chegara)
    await db.collection('restaurants').doc('r_ok').collection('menu_items').doc('dish_back').set({
      name: 'Lagmon', price: 30000, available: true, stopUntil: admin.firestore.Timestamp.fromMillis(Date.now() - 3600000) });
    await call({ targetType: 'restaurant_item', restaurantId: 'r_ok', targetId: 'dish_back', reason: 'spam' }, BUYER);
    assert.strictEqual((await reportsOf(BUYER)).length, 3);
  });

  await check('C3 parallel 5 ta bir xil chaqiruv — faqat BITTA hujjat (tranzaksiya qulfi)', async () => {
    const outs = await Promise.all(Array.from({ length: 5 }, () => call({ targetType: 'realty_listing', targetId: 'L_ok', reason: 'fraud' }, BUYER2)));
    const docs = await reportsOf(BUYER2);
    assert.strictEqual(docs.length, 1, `hujjatlar: ${docs.length}`);
    assert.ok(outs.every((o) => o.reportId === docs[0].id));
    assert.strictEqual(outs.filter((o) => !o.duplicate).length, 1);
    const d = docs[0].data();
    assert.strictEqual(d.type, 'realty_content');
    assert.strictEqual(d.title, 'Uy sotiladi');
    assert.strictEqual(d.restaurantId, undefined);
    assert.strictEqual(JSON.stringify(d).includes(REALTOR), false, 'egasining telefoni yozilmaydi');
  });

  await check('C3b sarlavhasiz eski e\'lon — sarlavha ID, erkin matn (telefon bo\'lishi mumkin) olinmaydi', async () => {
    await db.collection('realty_listings').doc('L_old').set({ ownerKey: 'key_realtor', text: 'Tel 901234567 qo\'ng\'iroq qiling', status: 'active', expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000) });
    const r = await call({ targetType: 'realty_listing', targetId: 'L_old', reason: 'spam' }, BUYER2);
    const d = (await db.collection('reports').doc(r.reportId).get()).data();
    assert.strictEqual(d.title, '#L_old');
    assert.strictEqual(JSON.stringify(d).includes('901234567'), false);
  });

  await check('C4 admin yopgach (adminResolveDatingReport) — qayta shikoyat YANGI hujjat; eskisi resolvedBy bilan tarixda', async () => {
    const ADMIN = '998913000099';
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await fns.adminResolveDatingReport.run({ adminPhone: ADMIN, reportId: restId }, ctxOf(ADMIN));
    const old = (await db.collection('reports').doc(restId).get()).data();
    assert.strictEqual(old.status, 'resolved');
    assert.ok(old.resolvedBy);
    assert.ok(old.resolvedAt);
    const res = await call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'fraud' }, BUYER);
    assert.notStrictEqual(res.reportId, restId);
    assert.strictEqual(res.duplicate, undefined);
    assert.strictEqual((await db.collection('reports').doc(restId).get()).data().status, 'resolved');
  });

  await check(`C5 kunlik chegara: ${DAILY_LIMIT} ta (tur bo'yicha) — keyingisi COMPLAINT_LIMIT`, async () => {
    const LIM = '998913000077';
    const batch = db.batch();
    for (let i = 0; i < DAILY_LIMIT; i++) {
      batch.set(db.collection('reports').doc(), { type: 'realty_content', reporterId: LIM, targetId: `x${i}`, status: 'open', createdAt: T.now() });
    }
    await batch.commit();
    await expectCode(call({ targetType: 'realty_listing', targetId: 'L_ok', reason: 'spam' }, LIM), 'COMPLAINT_LIMIT');
    // boshqa tur (restoran) — o'z chegarasi
    const ok = await call({ targetType: 'restaurant', targetId: 'r_ok', reason: 'spam' }, LIM);
    assert.strictEqual(ok.ok, true);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
