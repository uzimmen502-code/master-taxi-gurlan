/**
 * HISOBNI O'CHIRISH — yakuniy qadamlar: ochiq kontent, provayder/chat, shaxsiy maydonlarni tozalash
 * (`account_deletion_content.js`), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-content \
 *     "node test/account_deletion_content_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-del-content';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const core = require('../account_deletion_core');
const { createAccountDeletion } = require('../account_deletion');
const { createHider } = require('../account_deletion_hide');

const U = '998901112233';
const U9 = '901112233';
const OTHER = '998907776655';
const DAY = 24 * 60 * 60 * 1000;
const T0 = 1_800_000_000_000;
let T = T0;
const storage = [];

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const exists = async (p) => (await db.doc(p).get()).exists;
const data = async (p) => (await db.doc(p).get()).data();
const count = async (p) => (await db.collection(p).get()).size;
const svc = () => createAccountDeletion({
  db, admin, now: () => T, log: () => {},
  auth: { getUserByPhoneNumber: async () => { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; }, deleteUser: async () => {} },
  hiders: [createHider({ db, admin })],
  deleteStoragePrefix: async (p) => { storage.push(p); },
  deleteStoragePath: async () => {},
});
const step = (s, name) => s.STEPS.find((x) => x.name === name);

async function seed() {
  T = T0;
  storage.length = 0;
  await clearEmulator();
  await db.collection('settings').doc('account_deletion').set({ enabled: true });
  await db.collection('users').doc(U).set({ role: 'user', phone: `+${U}`, realtyOwnerKey: 'rk1', bonusBalance: 0 });
  await db.collection('users').doc(OTHER).set({ role: 'user', phone: `+${OTHER}`, bonusBalance: 0 });
  // ochiq kontent
  await db.collection('ads').doc('a1').set({ ownerId: U, status: 'active' });
  await db.collection('ads').doc('a4').set({ authorPhone: U9, status: 'active', type: 'work' });
  await db.collection('ads').doc('aX').set({ ownerId: OTHER, status: 'active' });
  await db.collection('tv_clips').doc('c1').set({ ownerPhone: U, status: 'active' });
  await db.collection('tv_clips').doc('c1').collection('comments').doc('k1').set({ authorPhone: OTHER, text: 'zo\'r' });
  await db.collection('tv_clips').doc('c3').set({ ownerPhone: U9, status: 'active' });
  await db.collection('tv_clips').doc('cX').set({ ownerPhone: OTHER, status: 'active' });
  await db.collection('tv_shop_items').doc('i1').set({ ownerPhone: U, status: 'active' });
  await db.collection('tv_shop_items').doc('iX').set({ ownerPhone: OTHER, status: 'active' });
  await db.collection('businesses').doc('b1').set({ ownerId: U, name: 'Avto' });
  await db.collection('businesses').doc('bX').set({ ownerId: OTHER, name: 'Boshqa' });
  await db.collection('yuk_listings').doc('y1').set({ ownerId: U, status: 'active' });
  await db.collection('yuk_local_drivers').doc('yl1').set({ ownerId: U });
  await db.collection('realty_listings').doc('r1').set({ ownerKey: 'rk1', status: 'active' });
  await db.collection('realty_listings').doc('r1').collection('private').doc('detail').set({ phone: U, lat: 41.1 });
  await db.collection('realty_listings').doc('rX').set({ ownerKey: 'rk_other', status: 'active' });
  await db.collection('wholesale_products').doc('w1').set({ sellerId: U, status: 'active' });
  await db.collection('wholesale_products').doc('wX').set({ sellerId: OTHER, status: 'active' });
  await db.collection('tv_shops').doc(U).set({ ownerPhone: U, name: 'Do\'kon' });
  await db.collection('tv_public_profiles').doc(U).set({ name: 'Ali' });
  await db.collection('tv_public_profiles').doc(U).collection('followers').doc(OTHER).set({ at: 1 });
  await db.collection('tv_public_profiles').doc(OTHER).set({ name: 'Vali' });
  await db.collection('wholesale_sellers').doc(U).set({ phone: U, address: 'Gurlan' });
  await db.collection('ev_charging_stations').doc('e1').set({ createdBy: U, isActive: true, name: 'Stansiya' });
  await db.collection('ev_charging_stations').doc('e2').set({ createdBy: OTHER, isActive: true });
  // provayder va chat
  await db.collection('drivers').doc(U).set({ name: 'Ali', fcmToken: 't' });
  await db.collection('drivers').doc(OTHER).set({ name: 'Vali' });
  await db.collection('queue').doc(U).set({ driverPhone: U, isActive: true });
  await db.collection('driver_requests').doc(U).set({ passport: 'AA123' });
  await db.collection('couriers').doc(U).set({ name: 'Ali' });
  await db.collection('intercity_drivers').doc(U).set({ isActive: true });
  await db.collection('intercity_drivers').doc(U).collection('clients').doc(OTHER).set({ n: 1 });
  await db.collection('provider_presence').doc(U).set({ isOnline: false });
  await db.collection('schedules').doc('s1').set({ driverId: U, isActive: true });
  await db.collection('schedules').doc('sX').set({ driverId: OTHER, isActive: true });
  await db.collection('support_chats').doc(U).set({ userPhone: U });
  await db.collection('support_chats').doc(U).collection('messages').doc('m1').set({ text: 'salom' });
  await db.collection('support_chats').doc(OTHER).set({ userPhone: OTHER });
  await db.collection('relatives').doc(U).collection('people').doc('p1').set({ name: 'Aka', phone: '998900000001' }); // virtual ota
  // yozuvlar (shaxsiy maydonlar)
  await db.collection('orders').doc('o1').set({ userPhone: U, status: 'completed', userName: 'Ali', address: 'Gurlan 5', note: 'eshik', total: 10000, phone: U });
  await db.collection('orders').doc('oX').set({ userPhone: OTHER, status: 'completed', userName: 'Vali', address: 'Xiva' });
  await db.collection('trips').doc('t1').set({ userPhone: U, status: 'completed', userName: 'Ali', fromAddr: 'A', toAddr: 'B', acceptedDriverName: 'Haydovchi', acceptedDriverPhone: OTHER, price: 5000 });
  await db.collection('trips').doc('t2').set({ userPhone: OTHER, driverId: U, status: 'completed', userName: 'Vali', fromAddr: 'C', acceptedDriverName: 'Ali', acceptedDriverPhone: U, acceptedDriverCar: 'Damas', acceptedDriverPlate: '90A' });
  await db.collection('trips').doc('t3').set({ userPhone: OTHER, acceptedDriverId: U, status: 'completed', acceptedDriverName: 'Ali', acceptedDriverPhone: U });
  await db.collection('restaurant_bookings').doc('rb1').set({ userPhone: U, status: 'completed', userName: 'Ali' });
  await db.collection('wallet_topup_requests').doc('tp1').set({ uid: U, status: 'credited', amount: 50000, telegramUserId: '1', telegramChatId: '2', telegramUsername: 'ali' });
  await db.collection('wallet_withdraw_requests').doc('wd1').set({ uid: U, status: 'paid', amount: 20000, payoutCardNumber: '8600123412341234', payoutCardHolder: 'ALI', telegramUserId: '1' });
}

async function main() {
  await seed();

  await check('K1 to\'liq ijro: ochiq kontent o\'chadi, begonaniki qoladi, ost-kolleksiyalar bilan', async () => {
    const s = svc();
    await s.request(U);
    T = T0 + 11 * DAY;
    const r = await s.execute(U);
    assert.strictEqual(r.status, 'DONE', JSON.stringify(r));
    for (const p of ['ads/a1', 'ads/a4', 'tv_clips/c1', 'tv_clips/c1/comments/k1', 'tv_clips/c3', 'tv_shop_items/i1', 'businesses/b1',
      'yuk_listings/y1', 'yuk_local_drivers/yl1', 'realty_listings/r1', 'realty_listings/r1/private/detail', 'wholesale_products/w1',
      `tv_shops/${U}`, `tv_public_profiles/${U}`, `tv_public_profiles/${U}/followers/${OTHER}`, `wholesale_sellers/${U}`]) {
      assert.strictEqual(await exists(p), false, `${p} o'chmadi`);
    }
    for (const p of ['ads/aX', 'tv_clips/cX', 'tv_shop_items/iX', 'businesses/bX', 'realty_listings/rX', 'wholesale_products/wX',
      `tv_public_profiles/${OTHER}`, `drivers/${OTHER}`, 'schedules/sX', `support_chats/${OTHER}`, 'orders/oX']) {
      assert.strictEqual(await exists(p), true, `begona ${p} o'chib ketdi`);
    }
  });

  await check('K2 Storage prefikslari (ikki shakl) so\'raladi', () => {
    for (const p of [`ads/${U}/`, `ads/${U9}/`, `wholesale_products/${U}/`, `profiles/${U}/`, `relatives/${U}/`,
      `tv_clips/${U}/`, `tv_profile/${U}/`, `tv_shop/${U}/`]) {
      assert.ok(storage.includes(p), `${p} yo'q: ${storage.join(',')}`);
    }
  });

  await check('K3 EV stansiya: qoladi, egalik olinadi, yashirilgan bo\'lsa qayta faol; begonaniki tegilmaydi', async () => {
    const e1 = await data('ev_charging_stations/e1');
    assert.strictEqual(e1.createdBy, '');
    assert.strictEqual(e1.isActive, true);
    assert.ok(!('hiddenByAccountDeletion' in e1));
    assert.strictEqual(e1.name, 'Stansiya');
    assert.strictEqual((await data('ev_charging_stations/e2')).createdBy, OTHER);
  });

  await check('K4 provayder/chat/qarindosh: o\'chadi (virtual ota ost-kolleksiyasi ham), begonaniki qoladi', async () => {
    for (const p of [`drivers/${U}`, `queue/${U}`, `driver_requests/${U}`, `couriers/${U}`, `intercity_drivers/${U}`,
      `intercity_drivers/${U}/clients/${OTHER}`, `provider_presence/${U}`, 'schedules/s1', `support_chats/${U}`,
      `support_chats/${U}/messages/m1`, `relatives/${U}/people/p1`]) {
      assert.strictEqual(await exists(p), false, `${p} o'chmadi`);
    }
  });

  await check('K5 yozuvlar anonimlashadi: shaxsiy maydonlar ketadi, moliyaviy kalit va summalar qoladi', async () => {
    const o = await data('orders/o1');
    for (const f of ['userName', 'address', 'note']) assert.ok(!(f in o), `orders.${f} qoldi`);
    assert.strictEqual(o.userPhone, U);
    assert.strictEqual(o.total, 10000);
    const t1 = await data('trips/t1');
    for (const f of ['userName', 'fromAddr', 'toAddr']) assert.ok(!(f in t1), `trips.t1.${f} qoldi`);
    assert.strictEqual(t1.acceptedDriverName, 'Haydovchi'); // begona haydovchi ma'lumoti tegilmadi
    assert.strictEqual(t1.price, 5000);
    const t2 = await data('trips/t2');
    for (const f of ['acceptedDriverName', 'acceptedDriverPhone', 'acceptedDriverCar', 'acceptedDriverPlate']) {
      assert.ok(!(f in t2), `trips.t2.${f} qoldi`);
    }
    assert.strictEqual(t2.userName, 'Vali'); // yo'lovchining (begona) ismi tegilmadi
    assert.ok(!('acceptedDriverName' in (await data('trips/t3'))));
    assert.ok(!('userName' in (await data('restaurant_bookings/rb1'))));
    const tp = await data('wallet_topup_requests/tp1');
    assert.ok(!('telegramUsername' in tp) && !('telegramChatId' in tp) && tp.amount === 50000);
    const wd = await data('wallet_withdraw_requests/wd1');
    assert.ok(!('payoutCardNumber' in wd) && !('payoutCardHolder' in wd) && wd.amount === 20000);
    // begona yozuv tegilmadi
    assert.strictEqual((await data('orders/oX')).address, 'Xiva');
  });

  await check('K6 qadamlarni qayta ishga tushirish (idempotent): xato yo\'q, 2-marta o\'zgarish 0', async () => {
    const s = svc();
    const identity = await core.resolveIdentity(db, U);
    const a = await step(s, 'anonymize_records').run({ identity, uid: U });
    assert.deepStrictEqual(Object.values(a).reduce((x, y) => x + y, 0), 0);
    const b = await step(s, 'delete_public_content').run({ identity, uid: U });
    assert.strictEqual(b.ads + b.tvClips + b.businesses + b.realty, 0);
    await step(s, 'delete_provider_and_support').run({ identity, uid: U });
    await step(s, 'release_ev_stations').run({ identity, uid: U });
  });

  await check('K7 sahifalash: 450 ta e\'lon va 450 ta buyurtma — hammasi o\'chadi/tozalanadi (kursor adashmaydi)', async () => {
    await seed();
    for (let i = 0; i < 450; i += 400) {
      const b = db.batch();
      for (let j = i; j < Math.min(i + 400, 450); j++) {
        b.set(db.collection('ads').doc(`bulk${j}`), { ownerId: U, status: 'active' });
        b.set(db.collection('orders').doc(`bo${j}`), { userPhone: U, status: 'completed', userName: 'Ali', address: 'x' });
      }
      await b.commit();
    }
    const s = svc();
    const identity = await core.resolveIdentity(db, U);
    const del = await step(s, 'delete_public_content').run({ identity, uid: U });
    assert.ok(del.ads >= 451, `o'chirilgan e'lonlar: ${del.ads}`);
    assert.strictEqual((await db.collection('ads').where('ownerId', '==', U).get()).size, 0);
    const an = await step(s, 'anonymize_records').run({ identity, uid: U });
    assert.ok(an.orders >= 451, `tozalangan buyurtmalar: ${an.orders}`);
    const left = (await db.collection('orders').where('userPhone', '==', U).get()).docs.filter((d) => 'userName' in d.data() || 'address' in d.data());
    assert.strictEqual(left.length, 0);
    assert.strictEqual((await db.collection('ads').doc('aX').get()).exists, true);
  });
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
