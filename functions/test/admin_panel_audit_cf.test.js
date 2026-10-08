/**
 * Admin panel ↔ ilova muvofiqlik auditi (2026-10-07/08) — Cloud Functions,
 * HAQIQIY Firestore Emulator + ledger bilan. functions/index.js export'larini
 * `.run(data, context)` orqali chaqiradi.
 *
 *   firebase emulators:exec --config <cfg> --only firestore,auth \
 *     --project demo-admin-audit "node <repo>/functions/test/admin_panel_audit_cf.test.js"
 *
 * M bo'limi (admin PIN bilan kirish) Auth emulator talab qiladi; repo
 * `firebase.json`da `auth` emulyatori yo'q, shuning uchun alohida config:
 *   { "firestore": {"rules": "<repo>/firestore.rules"},
 *     "emulators": {"firestore": {"port": 18180}, "auth": {"port": 19099},
 *                   "ui": {"enabled": false}} }
 * (portlar 15000 dan yuqori — Windows Hyper-V rezervi). Auth'siz faqat
 * M8/M9 yiqiladi.
 *
 * Qulflanadi:
 *   A  assertAdmin — anonim sessiya klient `adminPhone` bilan kira olmaydi
 *   B  admin buyurtma statusi: o'tish jadvali, rad etishda hamyon + zaxira
 *      qaytadi, batch holati o'zgarganini o'tkazib yuboradi
 *   C  customerCancelOrder zaxirali buyurtmada yiqilmaydi (reads-before-writes)
 *   D  grantBirthdayBonus — summa serverdan, yil faqat joriy
 *   E  rejectPayout — faqat finance/superadmin, tranzaksiya, sabab saqlanadi
 *   F  saveDatingProfile — bloklangan profil o'zini ocholmaydi
 *   G  adminUpdateJobAdStatus — qayta ochishda muddat yangilanadi
 *   H  renewTvAd — bloklangan reklama uchun pul yechilmaydi
 *   I  requestWalletWithdraw / createTelegramLinkCode — anonim begona raqam
 *   J  adminResetTaxiDriversRegistry — superadmin, dry-run, faqat `driver`
 *   K  adminResolveEvReport — reportCount kamayadi, idempotent
 *   L  sendSupportChatReply — qo'lda javob `systemOrder: false` (push ketadi)
 *   M  adminWebSignIn — telefon + shaxsiy PIN; qulf; adminSetAdminPin /
 *      adminChangeOwnPin (ega qarori D-1)
 *   R  adminResetItemSoldToday — bitta mahsulot reseti ochiq to'lanmagan
 *      buyurtma rezervini saqlaydi (O-8), parallel rad etish bilan izchil
 *   S  intercityCreateBooking — admin to'xtatgan (suspended) haydovchining
 *      ochiq qolgan e'loniga bron yo'q (O-13)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-admin-audit';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const ledger = require('../settlement_ledger');

const ADMIN = '998901000010';
const SUPER = '998901000011';
const FINANCE = '998901000012';
const DISPATCHER = '998901000013';
const CUSTOMER = '998901000020';
const OTHER = '998901000021';
const DRIVER = '998902000030';

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const ANON = { auth: { uid: 'anon_uid_x', token: {} } };

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function rejectsWith(promise, code, msgPart) {
  try {
    await promise;
  } catch (e) {
    const c = e.code || (e.httpErrorCode && e.httpErrorCode.status) || '';
    if (code && !String(c).includes(code) && String(e.code) !== code) {
      throw new Error(`kutilgan ${code}, keldi ${c} (${e.message})`);
    }
    if (msgPart && !String(e.message).includes(msgPart)) {
      throw new Error(`xabar "${msgPart}" emas: ${e.message}`);
    }
    return e;
  }
  throw new Error(`rad etilishi kerak edi (${code})`);
}
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset() {
  await Promise.all(['users', 'orders', 'bread_products', 'wallet_idempotency',
    'payout_requests', 'dating_profiles', 'ads', 'tv_clips', 'settings',
    'queue', 'intercity_drivers', 'schedules', 'driver_requests', 'drivers',
    'admin_audit', 'admin_credentials', 'ev_charging_stations', 'support_chats', 'admin_news',
    ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(FINANCE).set({ role: 'finance' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(CUSTOMER).set({ role: 'user', bonusBalance: 0 });
  await db.collection('users').doc(OTHER).set({ role: 'user', bonusBalance: 50000 });
}
const userBal = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance || 0;
async function journalBalanced() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((a, l) => a + (l.dr || 0), 0);
    const cr = legs.reduce((a, l) => a + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id} Σdr ${dr} != Σcr ${cr}`);
  }
  return s.size;
}
function order(extra = {}) {
  return {
    userPhone: CUSTOMER, type: 'bread', status: 'new', fulfillmentStatus: 'pending',
    totalPrice: 10000, balanceApplied: 3000,
    inventoryDecrements: [{ kind: 'bread', id: 'b1', qty: 2, label: 'Non' }],
    ...extra,
  };
}
const setStatus = (orderId, status, who = ADMIN) =>
  fns.adminSetOrderStatus.run({ adminPhone: who, orderId, status }, ctxOf(who));

async function main() {
  // ── A. assertAdmin ───────────────────────────────────────────────────
  await reset();
  await db.collection('orders').doc('o1').set(order());
  await check('A1 anonim sessiya + admin raqami (adminPhone) → rad', async () => {
    await rejectsWith(
      fns.adminSetOrderStatus.run({ adminPhone: ADMIN, orderId: 'o1', status: 'accepted' }, ANON),
      'permission-denied', 'Phone login required');
    assert.strictEqual((await db.collection('orders').doc('o1').get()).data().status, 'new');
  });
  await check('A2 oddiy foydalanuvchi token + admin raqami → rad (mismatch)', async () => {
    await rejectsWith(
      fns.adminSetOrderStatus.run({ adminPhone: ADMIN, orderId: 'o1', status: 'accepted' }, ctxOf(OTHER)),
      'permission-denied');
  });
  await check('A3 oddiy foydalanuvchi o\'z tokeni bilan → rad (Admin only)', async () => {
    await rejectsWith(
      fns.adminSetOrderStatus.run({ orderId: 'o1', status: 'accepted' }, ctxOf(OTHER)),
      'permission-denied', 'Admin only');
  });
  await check('A4 haqiqiy admin (token) — adminPhone bo\'lmasa ham ishlaydi', async () => {
    const r = await fns.adminSetOrderStatus.run({ orderId: 'o1', status: 'accepted' }, ctxOf(ADMIN));
    assert.strictEqual(r.ok, true);
  });

  // ── B. Admin buyurtma statusi ───────────────────────────────────────
  await reset();
  await db.collection('bread_products').doc('b1').set({ totalStock: 10, soldToday: 5 });
  await db.collection('orders').doc('o2').set(order());
  await check('B1 rad etish → hamyon 3000 qaytadi, zaxira −2, ledger balansda', async () => {
    const r = await setStatus('o2', 'rejected');
    assert.strictEqual(r.walletRefund, 3000);
    const o = (await db.collection('orders').doc('o2').get()).data();
    assert.strictEqual(o.status, 'rejected');
    assert.strictEqual(o.fulfillmentStatus, 'cancelled');
    assert.strictEqual(o.rejectedBy, ADMIN);
    assert.strictEqual(await userBal(CUSTOMER), 3000);
    assert.strictEqual((await db.collection('bread_products').doc('b1').get()).data().soldToday, 3);
    const pc = (await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(CUSTOMER)).get()).data();
    assert.strictEqual(pc.balance, 3000);
    assert.ok(await journalBalanced() >= 1);
    const wl = await db.collection('users').doc(CUSTOMER).collection('wallet_ledger').get();
    assert.strictEqual(wl.size, 1);
    assert.strictEqual(wl.docs[0].data().type, 'order_cancel_refund');
  });
  await check('B2 qayta rad etish → o\'zgarmaydi, IKKINCHI qaytarish yo\'q', async () => {
    const r = await setStatus('o2', 'rejected');
    assert.strictEqual(r.walletRefund, 0);
    assert.strictEqual(await userBal(CUSTOMER), 3000);
    assert.strictEqual((await db.collection('bread_products').doc('b1').get()).data().soldToday, 3);
  });
  await check('B3 rad etilgan buyurtmani `accepted`ga tiriltirib bo\'lmaydi', async () => {
    const e = await rejectsWith(setStatus('o2', 'accepted'), 'failed-precondition');
    assert.strictEqual(e.details.code, 'ORDER_TRANSITION_NOT_ALLOWED');
  });
  await db.collection('orders').doc('o3').set(order({ status: 'cancelled', fulfillmentStatus: 'cancelled' }));
  await db.collection('orders').doc('o4').set(order({ balanceApplied: 0 }));
  await check('B4 batch: mijoz bekor qilgani o\'tkaziladi, yangisi qabul qilinadi', async () => {
    const r = await fns.adminSetOrderStatusBatch.run(
      { orderIds: ['o3', 'o4', 'o4'], status: 'accepted' }, ctxOf(ADMIN));
    assert.strictEqual(r.updated, 1);
    assert.strictEqual(r.skipped.length, 1);
    assert.strictEqual(r.skipped[0].orderId, 'o3');
    assert.strictEqual((await db.collection('orders').doc('o3').get()).data().status, 'cancelled');
    assert.strictEqual((await db.collection('orders').doc('o4').get()).data().status, 'accepted');
  });
  await check('B5 sakrash yo\'q: new → delivered rad', async () => {
    await db.collection('orders').doc('o5').set(order({ balanceApplied: 0 }));
    await rejectsWith(setStatus('o5', 'delivered'), 'failed-precondition');
  });
  await check('B6 accepted → ready; «Kuryerda» (ready → in_delivery) admin uchun YO\'Q (ega qarori)', async () => {
    for (const s of ['accepted', 'ready']) await setStatus('o5', s);
    const e = await rejectsWith(setStatus('o5', 'in_delivery'), 'failed-precondition');
    assert.strictEqual(e.details.code, 'ORDER_TRANSITION_NOT_ALLOWED');
    assert.strictEqual((await db.collection('orders').doc('o5').get()).data().status, 'ready');
  });
  await check('B8 kuryer olgan, TO\'LANMAGAN buyurtma — «Yetkazildi» rad (ORDER_NOT_PAID)', async () => {
    await db.collection('orders').doc('o8').set(order({
      status: 'in_delivery', fulfillmentStatus: 'courier_picked', courierId: '998903000001',
      paymentStatus: 'pending', balanceApplied: 0,
    }));
    const e = await rejectsWith(setStatus('o8', 'delivered'), 'failed-precondition');
    assert.strictEqual(e.details.code, 'ORDER_NOT_PAID');
    assert.strictEqual((await db.collection('orders').doc('o8').get()).data().paymentStatus, 'pending');
  });
  await check('B9 to\'langan buyurtma — «Yetkazildi» ishlaydi', async () => {
    await db.collection('orders').doc('o8').update({ paymentStatus: 'paid' });
    await setStatus('o8', 'delivered');
    const o = (await db.collection('orders').doc('o8').get()).data();
    assert.strictEqual(o.status, 'delivered');
    assert.strictEqual(o.fulfillmentStatus, 'completed');
  });
  await check('B10 kuryeri bor buyurtmani navbatga qaytarib bo\'lmaydi', async () => {
    await db.collection('orders').doc('o9').set(order({
      status: 'in_delivery', fulfillmentStatus: 'courier_picked', courierId: '998903000001', balanceApplied: 0,
    }));
    const e = await rejectsWith(setStatus('o9', 'ready'), 'failed-precondition');
    assert.strictEqual(e.details.code, 'ORDER_HELD_BY_COURIER');
  });
  await check('B11 eski «Kuryerda»dan qolgan kuryersiz (etim) buyurtma navbatga qaytadi', async () => {
    await db.collection('orders').doc('o10').set(order({
      status: 'in_delivery', fulfillmentStatus: 'courier_picked', balanceApplied: 0,
    }));
    await setStatus('o10', 'ready');
    const o = (await db.collection('orders').doc('o10').get()).data();
    assert.strictEqual(o.status, 'ready');
    assert.strictEqual(o.fulfillmentStatus, 'confirmed');
  });
  await check('B7 kuryerdagi buyurtmani admin rad eta olmaydi', async () => {
    await db.collection('orders').doc('o6').set(order({ status: 'ready', fulfillmentStatus: 'courier_picked' }));
    const e = await rejectsWith(setStatus('o6', 'rejected'), 'failed-precondition');
    assert.strictEqual(e.details.code, 'ORDER_HELD_BY_COURIER');
    assert.strictEqual(await userBal(CUSTOMER), 3000);
  });

  // ── C. customerCancelOrder (zaxirali buyurtma) ──────────────────────
  await reset();
  await db.collection('bread_products').doc('b1').set({ totalStock: 10, soldToday: 5 });
  await db.collection('orders').doc('c1').set(order({ status: 'accepted', fulfillmentStatus: 'confirmed' }));
  await check('C1 mijoz bekor qiladi: zaxirali buyurtmada YIQILMAYDI, pul + zaxira qaytadi', async () => {
    const r = await fns.customerCancelOrder.run({ orderId: 'c1' }, ctxOf(CUSTOMER));
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.walletRefund, 3000);
    const o = (await db.collection('orders').doc('c1').get()).data();
    assert.strictEqual(o.status, 'cancelled');
    assert.strictEqual(o.cancelledBy, CUSTOMER);
    assert.strictEqual(await userBal(CUSTOMER), 3000);
    assert.strictEqual((await db.collection('bread_products').doc('b1').get()).data().soldToday, 3);
    await journalBalanced();
  });
  await check('C2 takroriy chaqiruv — ikkinchi qaytarish yo\'q', async () => {
    await fns.customerCancelOrder.run({ orderId: 'c1' }, ctxOf(CUSTOMER));
    assert.strictEqual(await userBal(CUSTOMER), 3000);
  });
  await check('C3 bekor qilingan buyurtmani admin rad etsa — ikkinchi qaytarish yo\'q', async () => {
    await rejectsWith(setStatus('c1', 'rejected'), 'failed-precondition');
    assert.strictEqual(await userBal(CUSTOMER), 3000);
  });
  await check('C4 begona mijoz boshqaning buyurtmasini bekor qila olmaydi', async () => {
    await db.collection('orders').doc('c2').set(order());
    await rejectsWith(fns.customerCancelOrder.run({ orderId: 'c2' }, ctxOf(OTHER)), 'permission-denied');
  });

  // ── C'. Eski 9 xonali users hujjati (hamyon auditi O-18) ────────────
  await reset();
  const LEGACY9 = '901000077';
  await db.collection('users').doc(LEGACY9).set({ role: 'user', bonusBalance: 0 });
  await db.collection('orders').doc('c9').set(order({ userPhone: `998${LEGACY9}`, inventoryDecrements: [] }));
  await check('C5 userPhone 12 xona, users hujjati eski 9 xona — qaytarish TOPILADI', async () => {
    const r = await setStatus('c9', 'rejected');
    assert.strictEqual(r.walletRefund, 3000);
    assert.strictEqual(await userBal(LEGACY9), 3000);
    assert.strictEqual((await db.collection('users').doc(`998${LEGACY9}`).get()).exists, false,
      'yangi 12 xonali hujjat yaratilmaydi');
    await journalBalanced();
  });
  await db.collection('orders').doc('c10').set(order({ userPhone: '998901000088', inventoryDecrements: [] }));
  await check('C6 hamyon hisobi umuman topilmasa — pul jimgina yo\'qolmaydi, bekor qilish rad', async () => {
    const e = await rejectsWith(setStatus('c10', 'rejected'), 'failed-precondition', 'REFUND_ACCOUNT_NOT_FOUND');
    assert.ok(e);
    assert.strictEqual((await db.collection('orders').doc('c10').get()).data().status, 'new');
  });
  await check('C7 batch: hisobi yo\'q buyurtma o\'tkaziladi, qolgani rad etiladi', async () => {
    await db.collection('orders').doc('c11').set(order({ userPhone: `998${LEGACY9}`, balanceApplied: 0, inventoryDecrements: [] }));
    const r = await fns.adminSetOrderStatusBatch.run({ orderIds: ['c10', 'c11'], status: 'rejected' }, ctxOf(ADMIN));
    assert.strictEqual(r.updated, 1);
    assert.deepStrictEqual(r.skipped.map((s) => [s.orderId, s.code]), [['c10', 'REFUND_ACCOUNT_NOT_FOUND']]);
    assert.strictEqual((await db.collection('orders').doc('c11').get()).data().status, 'rejected');
  });

  // ── D. grantBirthdayBonus ───────────────────────────────────────────
  await reset();
  const year = Number(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric' }).format(new Date()));
  await db.collection('settings').doc('app').set({ birthdayBonusAmount: 15000 });
  await check('D1 o\'tgan/kelajak yil → rad', async () => {
    await rejectsWith(fns.grantBirthdayBonus.run({ uid: CUSTOMER, year: year + 1, amount: 15000 }, ctxOf(ADMIN)),
      'invalid-argument', 'BIRTHDAY_BONUS_YEAR_NOT_CURRENT');
  });
  await check('D2 klient boshqa summa yuborsa → rad (summa serverdan)', async () => {
    await rejectsWith(fns.grantBirthdayBonus.run({ uid: CUSTOMER, year, amount: 999999 }, ctxOf(ADMIN)),
      'failed-precondition', 'BIRTHDAY_BONUS_AMOUNT_CHANGED');
    assert.strictEqual(await userBal(CUSTOMER), 0);
  });
  await check('D3 to\'g\'ri — server summasi (15000) qo\'shiladi', async () => {
    await fns.grantBirthdayBonus.run({ uid: CUSTOMER, year, amount: 15000 }, ctxOf(ADMIN));
    assert.strictEqual(await userBal(CUSTOMER), 15000);
    await journalBalanced();
  });
  await check('D4 shu yil ikkinchi marta — yo\'q', async () => {
    await fns.grantBirthdayBonus.run({ uid: CUSTOMER, year, amount: 15000 }, ctxOf(ADMIN)).catch(() => {});
    assert.strictEqual(await userBal(CUSTOMER), 15000);
  });
  await check('D5 mavjud bo\'lmagan foydalanuvchi → not-found (balans yaratilmaydi)', async () => {
    await rejectsWith(fns.grantBirthdayBonus.run({ uid: '998909999999', year }, ctxOf(ADMIN)), 'not-found');
    assert.strictEqual((await db.collection('users').doc('998909999999').get()).exists, false);
  });

  // ── E. rejectPayout ─────────────────────────────────────────────────
  await reset();
  await db.collection('payout_requests').doc('p1').set({ userPhone: OTHER, amount: 10000, status: 'pending' });
  await check('E1 admin endi rad eta olmaydi (Молия — finance bo\'limi)', async () => {
    await rejectsWith(fns.rejectPayout.run({ requestId: 'p1' }, ctxOf(ADMIN)), 'permission-denied');
  });
  await check('E2 finance rad etadi, sabab saqlanadi', async () => {
    await fns.rejectPayout.run({ requestId: 'p1', reason: 'Karta noto\'g\'ri' }, ctxOf(FINANCE));
    const p = (await db.collection('payout_requests').doc('p1').get()).data();
    assert.strictEqual(p.status, 'rejected');
    assert.strictEqual(p.rejectedReason, 'Karta noto\'g\'ri');
    assert.strictEqual(p.rejectedBy, FINANCE);
  });
  await check('E3 pending bo\'lmagan so\'rov — rad', async () => {
    await rejectsWith(fns.rejectPayout.run({ requestId: 'p1' }, ctxOf(FINANCE)), 'failed-precondition');
  });

  // ── F. saveDatingProfile ────────────────────────────────────────────
  await reset();
  await db.collection('settings').doc('app').set({ datingAutoApprove: true });
  await db.collection('dating_profiles').doc(OTHER).set({ userId: OTHER, status: 'blocked' });
  const datingPayload = {
    gender: 'male', displayName: 'Aziz', birthYear: new Date().getFullYear() - 30,
    photos: [{ url: 'https://example.com/p.jpg', path: 'dating/x/p.jpg' }],
  };
  await check('F1 bloklangan profil egasi qayta saqlab ochib yubora olmaydi', async () => {
    await rejectsWith(fns.saveDatingProfile.run(datingPayload, ctxOf(OTHER)), 'permission-denied', 'DATING_PROFILE_BLOCKED');
    assert.strictEqual((await db.collection('dating_profiles').doc(OTHER).get()).data().status, 'blocked');
  });
  await check('F2 oddiy profil saqlanadi (regressiya yo\'q)', async () => {
    const r = await fns.saveDatingProfile.run(datingPayload, ctxOf(CUSTOMER));
    assert.strictEqual(r.ok, true);
  });

  // ── G. adminUpdateJobAdStatus ───────────────────────────────────────
  await reset();
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 3600 * 1000);
  await db.collection('ads').doc('j1').set({ type: 'work', status: 'completed', text: 'Ish', expiresAt: past });
  await check('G1 muddati o\'tgan e\'lonni qayta ochish — muddat yangilanadi (work: 3 kun)', async () => {
    await fns.adminUpdateJobAdStatus.run({ adId: 'j1', status: 'active' }, ctxOf(ADMIN));
    const a = (await db.collection('ads').doc('j1').get()).data();
    assert.strictEqual(a.status, 'active');
    const days = (a.expiresAt.toMillis() - Date.now()) / 86400000;
    assert.ok(days > 2.9 && days < 3.1, `muddat ${days} kun`);
  });
  await check('G2 blok — muddatga tegilmaydi', async () => {
    const before = (await db.collection('ads').doc('j1').get()).data().expiresAt.toMillis();
    await fns.adminUpdateJobAdStatus.run({ adId: 'j1', status: 'blocked' }, ctxOf(ADMIN));
    assert.strictEqual((await db.collection('ads').doc('j1').get()).data().expiresAt.toMillis(), before);
  });
  await check('G3 «Muddatni olib tashlash» (clearExpiresAt) ishlaydi', async () => {
    await fns.adminUpdateJobAd.run({ adId: 'j1', text: 'Ish', type: 'work', clearExpiresAt: true }, ctxOf(ADMIN));
    assert.strictEqual('expiresAt' in (await db.collection('ads').doc('j1').get()).data(), false);
  });

  // ── H. renewTvAd ────────────────────────────────────────────────────
  await reset();
  await db.collection('users').doc(OTHER).set({ role: 'user', bonusBalance: 500000 });
  await db.collection('tv_clips').doc('ad1').set({ category: 'ad', status: 'blocked', ownerPhone: OTHER, adScope: 'district' });
  await check('H1 bloklangan reklamani uzaytirish — rad, pul yechilmaydi', async () => {
    await rejectsWith(fns.renewTvAd.run(
      { idempotencyKey: 'k1', clipId: 'ad1', durationDays: 7, tier: 'basic' }, ctxOf(OTHER)),
    'failed-precondition', 'TV_AD_BLOCKED');
    assert.strictEqual(await userBal(OTHER), 500000);
  });

  // ── I. Hamyon (anonim) ──────────────────────────────────────────────
  await check('I1 anonim sessiya begona raqam hamyonidan yechish so\'ray olmaydi', async () => {
    await rejectsWith(fns.requestWalletWithdraw.run({ phone: OTHER, amount: 10000 }, ANON), 'permission-denied');
  });
  await check('I2 anonim sessiya begona raqamga Telegram bog\'lash kodini ola olmaydi', async () => {
    await rejectsWith(fns.createTelegramLinkCode.run({ phone: OTHER }, ANON), 'permission-denied');
  });
  await check('I3 begona token bilan boshqa raqam — rad', async () => {
    await rejectsWith(fns.createTelegramLinkCode.run({ phone: OTHER }, ctxOf(CUSTOMER)), 'permission-denied');
  });

  // ── J. adminResetTaxiDriversRegistry ────────────────────────────────
  await reset();
  await db.collection('queue').doc('q1').set({ taxiType: 'local' });
  await db.collection('drivers').doc(DRIVER).set({ taxiType: 'local' });
  await db.collection('drivers').doc(DISPATCHER).set({ taxiTypes: ['intercity'] });
  await db.collection('users').doc(DRIVER).set({ role: 'driver' });
  await check('J1 admin (superadmin emas) — rad', async () => {
    await rejectsWith(fns.adminResetTaxiDriversRegistry.run({}, ctxOf(ADMIN)), 'permission-denied');
  });
  await check('J2 superadmin standart chaqiruv — dry-run, hech narsa o\'chmaydi', async () => {
    const r = await fns.adminResetTaxiDriversRegistry.run({}, ctxOf(SUPER));
    assert.strictEqual(r.dryRun, true);
    assert.strictEqual(r.stats.queueDeleted, 1);
    assert.strictEqual(r.stats.driversReset, 2);
    assert.strictEqual(r.stats.usersRoleReset, 1);
    assert.deepStrictEqual(r.stats.usersRoleKept, { dispatcher: 1 });
    assert.strictEqual((await db.collection('queue').get()).size, 1);
  });
  await check('J3 ijro tasdiq matnisiz — rad', async () => {
    await rejectsWith(fns.adminResetTaxiDriversRegistry.run({ dryRun: false }, ctxOf(SUPER)), 'invalid-argument');
  });
  await check('J4 ijro: driver → user, dispatcher roli SAQLANADI, audit yoziladi', async () => {
    const r = await fns.adminResetTaxiDriversRegistry.run(
      { dryRun: false, confirmText: 'RESET_TAXI_DRIVERS' }, ctxOf(SUPER));
    assert.strictEqual(r.dryRun, false);
    assert.strictEqual((await db.collection('users').doc(DRIVER).get()).data().role, 'user');
    assert.strictEqual((await db.collection('users').doc(DISPATCHER).get()).data().role, 'dispatcher');
    assert.strictEqual((await db.collection('queue').get()).size, 0);
    const audit = await db.collection('admin_audit').get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().actor, SUPER);
  });

  // ── K. adminResolveEvReport ─────────────────────────────────────────
  await reset();
  const st = db.collection('ev_charging_stations').doc('s1');
  await st.set({ reportCount: 2, status: 'working' });
  await st.collection('reports').doc('r1').set({ reporterId: OTHER, resolved: false });
  await check('K1 hal qilish reportCount ni kamaytiradi', async () => {
    await fns.adminResolveEvReport.run({ stationId: 's1', reportId: 'r1' }, ctxOf(ADMIN));
    assert.strictEqual((await st.get()).data().reportCount, 1);
    assert.strictEqual((await st.collection('reports').doc('r1').get()).data().resolved, true);
  });
  await check('K2 ikkinchi marta — kamaymaydi (idempotent)', async () => {
    const r = await fns.adminResolveEvReport.run({ stationId: 's1', reportId: 'r1' }, ctxOf(ADMIN));
    assert.strictEqual(r.alreadyResolved, true);
    assert.strictEqual((await st.get()).data().reportCount, 1);
  });

  // ── L. sendSupportChatReply ─────────────────────────────────────────
  await check('L1 admin qo\'lda javobi `systemOrder: false` (trigger push yuboradi)', async () => {
    await fns.sendSupportChatReply.run({ chatId: CUSTOMER, text: 'Salom' }, ctxOf(ADMIN));
    const m = await db.collection('support_chats').doc(CUSTOMER).collection('messages').get();
    assert.strictEqual(m.size, 1);
    assert.strictEqual(m.docs[0].data().systemOrder, false);
    assert.strictEqual(m.docs[0].data().fromAdmin, true);
  });

  // ── O. Moderatsiya: bozor rad etishi va ish e'loni egasi tahriri ────
  await reset();
  await db.collection('ads').doc('mk1').set({ type: 'cheap_product', ownerId: OTHER, status: 'active', title: 'Velosiped' });
  await check('O1 admin bozor e\'lonini «Nofaol» qilsa — adminRejected: true; «Faol» — false', async () => {
    await fns.adminUpdateMarketAdStatus.run({ adId: 'mk1', status: 'inactive' }, ctxOf(ADMIN));
    assert.strictEqual((await db.collection('ads').doc('mk1').get()).data().adminRejected, true);
    await fns.adminUpdateMarketAdStatus.run({ adId: 'mk1', status: 'active' }, ctxOf(ADMIN));
    assert.strictEqual((await db.collection('ads').doc('mk1').get()).data().adminRejected, false);
  });
  const runAdUpdate = async (id, patch) => {
    const ref = db.collection('ads').doc(id);
    const before = await ref.get();
    await ref.update(patch);
    const after = await ref.get();
    await fns.onAdUpdate.run({ before, after }, { params: { adId: id } });
    return (await ref.get()).data();
  };
  await db.collection('settings').doc('app').set({ jobsAutoApprove: false });
  await db.collection('ads').doc('j1').set({
    type: 'work', status: 'active', text: 'Ishchi kerak', authorPhone: OTHER,
    moderatedAt: admin.firestore.Timestamp.fromMillis(1000),
  });
  await check('O2 QO\'LDA rejim: egasi tasdiqlangan ish e\'loni matnini o\'zgartirsa — qayta pending', async () => {
    const d = await runAdUpdate('j1', { text: 'Boshqa narsa sotaman', editedAt: new Date() });
    assert.strictEqual(d.status, 'pending');
    assert.strictEqual(d.moderationReason, 'owner_edit');
  });
  await db.collection('ads').doc('j2').set({
    type: 'work', status: 'active', text: 'Ishchi kerak', authorPhone: OTHER,
    moderatedAt: admin.firestore.Timestamp.fromMillis(1000),
  });
  await check('O3 admin tahriri (moderatedAt o\'zgaradi) — active qoladi', async () => {
    const d = await runAdUpdate('j2', { text: 'Admin tuzatdi', moderatedAt: admin.firestore.Timestamp.fromMillis(2000) });
    assert.strictEqual(d.status, 'active');
  });
  await check('O4 AVTO rejim: egasi tahriri — active qoladi', async () => {
    await db.collection('settings').doc('app').set({ jobsAutoApprove: true });
    const d = await runAdUpdate('j2', { text: 'Egasi tuzatdi', editedAt: new Date() });
    assert.strictEqual(d.status, 'active');
  });

  // ── P. changeDevicePhone — hisobni egallash teshigi ─────────────────
  await reset();
  await Promise.all(['device_bindings', 'device_aliases'].map(wipe));
  const H_ATT = 'a'.repeat(64);
  const H_VIC = 'b'.repeat(64);
  const ATTACKER = '998901000031';
  const VICTIM = '998901000032';
  const FRESH = '998901000033';
  await db.collection('device_bindings').doc(H_ATT).set({ phone: ATTACKER });
  await db.collection('device_aliases').doc(ATTACKER).set({ phone: ATTACKER, deviceFingerprintHash: H_ATT });
  await db.collection('device_bindings').doc(H_VIC).set({ phone: VICTIM });
  await db.collection('device_aliases').doc(VICTIM).set({ phone: VICTIM, deviceFingerprintHash: H_VIC });
  await db.collection('users').doc(ATTACKER).set({ phone: ATTACKER, role: 'user' });
  await db.collection('users').doc(VICTIM).set({ phone: VICTIM, role: 'user' });
  const change = (hash, newPhone, ctx) => fns.changeDevicePhone.run({ deviceFingerprintHash: hash, newPhone }, ctx);
  const aliasOf = async (p) => ((await db.collection('device_aliases').doc(p).get()).data() || {}).deviceFingerprintHash;
  await check('P1 anonim sessiya — rad', async () => {
    await rejectsWith(change(H_ATT, VICTIM, ANON), 'permission-denied');
  });
  await check('P2 o\'z qurilmasini boshqa odamning (bog\'langan) raqamiga ko\'chira olmaydi', async () => {
    await rejectsWith(change(H_ATT, VICTIM, ctxOf(ATTACKER)), 'failed-precondition', 'PHONE_BOUND_OTHER_DEVICE');
    assert.strictEqual(await aliasOf(VICTIM), H_VIC, 'jabrlanuvchi aliasi o\'zgarmadi');
    assert.strictEqual((await db.collection('device_bindings').doc(H_ATT).get()).data().phone, ATTACKER);
  });
  await check('P3 boshqa odamning qurilmasini (hash) o\'zgartira olmaydi', async () => {
    await rejectsWith(change(H_VIC, FRESH, ctxOf(ATTACKER)), 'permission-denied', 'DEVICE_NOT_YOURS');
  });
  await check('P4 bog\'lanmagan, lekin hisobi bor raqamga — rad', async () => {
    await db.collection('users').doc('901000034').set({ phone: '998901000034' });
    await rejectsWith(change(H_ATT, '998901000034', ctxOf(ATTACKER)), 'failed-precondition', 'PHONE_HAS_ACCOUNT');
  });
  await check('P5 qonuniy: o\'z qurilmasini bo\'sh raqamga ko\'chiradi', async () => {
    const r = await change(H_ATT, FRESH, ctxOf(ATTACKER));
    assert.strictEqual(r.ok, true);
    assert.strictEqual((await db.collection('device_bindings').doc(H_ATT).get()).data().phone, FRESH);
    assert.strictEqual(await aliasOf(FRESH), H_ATT);
    assert.strictEqual((await db.collection('device_aliases').doc(ATTACKER).get()).exists, false);
  });

  // ── Q. Marshrut/taksi IDOR: leaveDriverRole, cancel-after-accept, reyting ──
  await reset();
  await Promise.all(['trips', 'schedules', 'queue', 'drivers', 'intercity_drivers'].map(wipe));
  await db.collection('users').doc(DRIVER).set({ role: 'driver' });
  await db.collection('drivers').doc(DRIVER).set({ isOnline: true, totalRatings: 0, ratingSum: 0 });
  await check('Q1 leaveDriverRole: anonim / begona raqam — rad', async () => {
    await rejectsWith(fns.leaveDriverRole.run({ userPhone: DRIVER }, ANON), 'permission-denied');
    await rejectsWith(fns.leaveDriverRole.run({ userPhone: SUPER }, ctxOf(OTHER)), 'permission-denied');
    assert.strictEqual((await db.collection('users').doc(SUPER).get()).data().role, 'superadmin');
  });
  await check('Q2 leaveDriverRole: o\'zi — driver → user', async () => {
    await fns.leaveDriverRole.run({ userPhone: DRIVER, clientHandledCleanup: true }, ctxOf(DRIVER));
    assert.strictEqual((await db.collection('users').doc(DRIVER).get()).data().role, 'user');
  });
  await check('Q3 leaveDriverRole: haydovchi hujjati bor dispatcher roli saqlanadi', async () => {
    await fns.leaveDriverRole.run({ userPhone: DISPATCHER, clientHandledCleanup: true }, ctxOf(DISPATCHER));
    assert.strictEqual((await db.collection('users').doc(DISPATCHER).get()).data().role, 'dispatcher');
  });
  await db.collection('schedules').doc('s1').set({ seats: 4, seatsLeft: 2 });
  await db.collection('queue').doc(DRIVER).set({ seats: 4, seatsLeft: 2, isActive: true });
  await db.collection('trips').doc('mt1').set({
    taxiType: 'marshrut', status: 'accepted', userPhone: CUSTOMER, scheduleId: 's1', acceptedDriverId: DRIVER,
  });
  await check('Q4 cancel-after-accept: begona — rad', async () => {
    await rejectsWith(fns.marshrutPassengerCancelAfterAccept.run({ tripId: 'mt1' }, ctxOf(OTHER)), 'permission-denied');
    assert.strictEqual((await db.collection('trips').doc('mt1').get()).data().status, 'accepted');
  });
  await check('Q5 cancel-after-accept: egasi — bekor, o\'rin qaytadi (reads-before-writes tuzatildi)', async () => {
    await fns.marshrutPassengerCancelAfterAccept.run({ tripId: 'mt1' }, ctxOf(CUSTOMER));
    assert.strictEqual((await db.collection('trips').doc('mt1').get()).data().status, 'cancelled');
    assert.strictEqual((await db.collection('schedules').doc('s1').get()).data().seatsLeft, 3);
    assert.strictEqual((await db.collection('queue').doc(DRIVER).get()).data().seatsLeft, 3);
  });
  await db.collection('trips').doc('lt1').set({
    taxiType: 'local', status: 'completed', userPhone: CUSTOMER, acceptedDriverId: DRIVER, driverId: DRIVER,
  });
  await check('Q6 reyting: begona yo\'lovchi / boshqa haydovchi — rad', async () => {
    await rejectsWith(fns.updateDriverRating.run({ driverId: DRIVER, rating: 1, tripId: 'lt1' }, ctxOf(OTHER)), 'permission-denied');
    await rejectsWith(fns.updateDriverRating.run({ driverId: OTHER, rating: 1, tripId: 'lt1' }, ctxOf(CUSTOMER)), 'permission-denied');
  });
  await check('Q7 reyting: egasi bir marta (ikkinchisi sanalmaydi)', async () => {
    await fns.updateDriverRating.run({ driverId: DRIVER, rating: 5, tripId: 'lt1' }, ctxOf(CUSTOMER));
    await fns.updateDriverRating.run({ driverId: DRIVER, rating: 1, tripId: 'lt1' }, ctxOf(CUSTOMER));
    const d = (await db.collection('drivers').doc(DRIVER).get()).data();
    assert.strictEqual(d.totalRatings, 1);
    assert.strictEqual(d.avgRating, 5);
    assert.strictEqual((await db.collection('trips').doc('lt1').get()).data().passengerRating, 5);
  });

  // ── N. Gilam / sut — admin o'tishlari (custody) ─────────────────────
  await reset();
  await Promise.all(['carpet_wash_orders', 'agro_pickup_orders'].map(wipe));
  const carpet = (id, extra) => db.collection('carpet_wash_orders').doc(id).set({
    customerPhone: CUSTOMER, carpetCount: 2, status: 'new', pickupCourierId: '', returnCourierId: '', ...extra,
  });
  const setCarpet = (orderId, status) =>
    fns.adminSetCarpetWashStatus.run({ orderId, status }, ctxOf(ADMIN));
  await carpet('w1', { status: 'pickup_in_delivery', pickupCourierId: '998903000001' });
  await check('N1 gilam: kuryer yo\'lda — admin «Yuvish» qila olmaydi', async () => {
    await rejectsWith(setCarpet('w1', 'washing'), 'failed-precondition', 'CARPET_TRANSITION_NOT_ALLOWED');
  });
  await carpet('w2', { status: 'washing' });
  await check('N2 gilam AVA qo\'lida — «Bekor» rad', async () => {
    await rejectsWith(setCarpet('w2', 'cancelled'), 'failed-precondition');
    assert.strictEqual((await db.collection('carpet_wash_orders').doc('w2').get()).data().status, 'washing');
  });
  await check('N3 gilam: to\'g\'ri oqim washing → drying → ready → return_ready', async () => {
    for (const s of ['drying', 'ready', 'return_ready']) await setCarpet('w2', s);
    assert.strictEqual((await db.collection('carpet_wash_orders').doc('w2').get()).data().status, 'return_ready');
  });
  await check('N4 gilam: kuryer qadamini (return_in_delivery) admin yoza olmaydi', async () => {
    await rejectsWith(setCarpet('w2', 'return_in_delivery'), 'failed-precondition');
  });
  await carpet('w3', {});
  await check('N5 gilam: yangi → qabul (narx bilan) → olib ketishga tayyor; olinmaganda bekor', async () => {
    await fns.adminSetCarpetWashStatus.run({ orderId: 'w3', status: 'accepted', finalPrice: 40000 }, ctxOf(ADMIN));
    await setCarpet('w3', 'pickup_ready');
    await setCarpet('w3', 'cancelled');
    const o = (await db.collection('carpet_wash_orders').doc('w3').get()).data();
    assert.strictEqual(o.status, 'cancelled');
    assert.strictEqual(o.finalPrice, 40000);
  });
  const agro = (id, extra) => db.collection('agro_pickup_orders').doc(id).set({
    customerPhone: CUSTOMER, productType: 'milk', status: 'accepted', pickupCourierId: '', ...extra,
  });
  const setAgro = (orderId, status) =>
    fns.adminSetAgroPickupStatus.run({ orderId, status }, ctxOf(ADMIN));
  await agro('m1', { status: 'pickup_in_delivery', pickupCourierId: '998903000001' });
  await check('N6 sut: kuryer olgan vazifani admin «Olib ketildi» bilan yoza olmaydi', async () => {
    await rejectsWith(setAgro('m1', 'picked_up'), 'failed-precondition', 'AGRO_TRANSITION_NOT_ALLOWED');
  });
  await agro('m2', {});
  await check('N7 sut: admin qo\'lda yig\'ish (accepted → picked_up → completed) ishlaydi', async () => {
    await setAgro('m2', 'picked_up');
    await setAgro('m2', 'completed');
    assert.strictEqual((await db.collection('agro_pickup_orders').doc('m2').get()).data().status, 'completed');
  });
  await check('N8 sut: olingan mahsulotni bekor qilib bo\'lmaydi; yakunlanganni ham', async () => {
    await agro('m3', { status: 'picked_up' });
    await rejectsWith(setAgro('m3', 'cancelled'), 'failed-precondition');
    await rejectsWith(setAgro('m2', 'cancelled'), 'failed-precondition');
  });

  // ── R. Bitta mahsulot «сотилган = 0» — ochiq buyurtma rezervi saqlanadi (O-8) ──
  await reset();
  await Promise.all(['extra_products', 'food_inventory'].map(wipe));
  const resetItem = (kind, id, who = ADMIN) =>
    fns.adminResetItemSoldToday.run({ adminPhone: who, kind, id }, ctxOf(who));
  const sold = async (col, id) => (await db.collection(col).doc(id).get()).data().soldToday;
  await db.collection('bread_products').doc('b1').set({ name: 'Non', totalStock: 20, soldToday: 7 });
  await db.collection('orders').doc('r_open').set(order({ paymentStatus: 'unpaid' }));
  await db.collection('orders').doc('r_paid').set(order({ paymentStatus: 'paid' }));
  await db.collection('orders').doc('r_cancel').set(order({ paymentStatus: 'unpaid', status: 'cancelled', fulfillmentStatus: 'cancelled' }));
  await check('R1 anonim / oddiy foydalanuvchi — rad, soldToday o\'zgarmaydi', async () => {
    await rejectsWith(fns.adminResetItemSoldToday.run({ adminPhone: ADMIN, kind: 'bread', id: 'b1' }, ANON), 'permission-denied');
    await rejectsWith(fns.adminResetItemSoldToday.run({ kind: 'bread', id: 'b1' }, ctxOf(OTHER)), 'permission-denied');
    assert.strictEqual(await sold('bread_products', 'b1'), 7);
  });
  await check('R2 reset: ochiq to\'lanmagan buyurtma rezervi (2) qoladi; to\'langan/bekor sanalmaydi', async () => {
    const r = await resetItem('bread', 'b1');
    assert.deepStrictEqual([r.before, r.soldToday], [7, 2]);
    assert.strictEqual(await sold('bread_products', 'b1'), 2);
  });
  await check('R3 qayta chaqiruv — natija o\'sha (idempotent)', async () => {
    await resetItem('bread', 'b1');
    assert.strictEqual(await sold('bread_products', 'b1'), 2);
  });
  await check('R4 rezervsiz mahsulot → 0; hujjati yo\'q mahsulot yaratilmaydi', async () => {
    await db.collection('extra_products').doc('e1').set({ name: 'Kunjut', totalStock: 5, soldToday: 3 });
    await resetItem('extra', 'e1');
    assert.strictEqual(await sold('extra_products', 'e1'), 0);
    const r = await resetItem('extra', 'nope');
    assert.strictEqual(r.soldToday, 0);
    assert.strictEqual((await db.collection('extra_products').doc('nope').get()).exists, false);
  });
  await check('R5 eski food buyurtmasi (items.inventoryId) ham rezerv sifatida sanaladi', async () => {
    await db.collection('food_inventory').doc('plov').set({ totalStock: 30, soldToday: 9 });
    await db.collection('orders').doc('r_food').set({
      userPhone: CUSTOMER, type: 'food', status: 'new', paymentStatus: 'unpaid',
      items: [{ inventoryId: 'plov', qty: 3 }],
    });
    await resetItem('food', 'plov');
    assert.strictEqual(await sold('food_inventory', 'plov'), 3);
  });
  await check('R6 noto\'g\'ri kind / id — invalid-argument', async () => {
    await rejectsWith(resetItem('wine', 'b1'), 'invalid-argument');
    await rejectsWith(resetItem('bread', ''), 'invalid-argument');
  });
  await check('R7 parallel: reset + admin rad etishi (zaxira qaytadi) — oxiri doim 0, manfiy emas', async () => {
    await db.collection('bread_products').doc('b1').set({ name: 'Non', totalStock: 20, soldToday: 7 });
    await db.collection('orders').doc('r_paid').delete();
    await Promise.all([resetItem('bread', 'b1'), setStatus('r_open', 'rejected')]);
    assert.strictEqual((await db.collection('orders').doc('r_open').get()).data().status, 'rejected');
    assert.strictEqual(await sold('bread_products', 'b1'), 0);
  });

  // ── S. Shaharlararo: to'xtatilgan (suspended) haydovchiga bron yo'q (O-13) ──
  await reset();
  await Promise.all(['provider_capabilities', 'intercity_bookings', 'intercity_booking_locks',
    'intercity_passenger_locks', 'notifications'].map(wipe));
  const listing = (id) => db.collection('intercity_drivers').doc(id).set({
    phone: id, name: 'Haydovchi', isActive: true, seats: 4, price: 50000, from: 'Gurlan', to: 'Toshkent',
  });
  const capOf = (acc, status) => db.collection('provider_capabilities').doc(acc).set({ status: { taxi: status } });
  const book = (driverId, who = CUSTOMER) =>
    fns.intercityCreateBooking.run({ driverId, passengers: 1, pricePerSeat: 50000 }, ctxOf(who));
  const seatsOf = async (id) => (await db.collection('intercity_drivers').doc(id).get()).data().seats;
  await listing(DRIVER);
  await db.collection('users').doc(DRIVER).set({ role: 'driver', accountId: 'acc_drv' });
  await capOf('acc_drv', 'suspended');
  await check('S1 suspended haydovchi — bron rad (driver_inactive), o\'rin va bron yozilmaydi', async () => {
    await rejectsWith(book(DRIVER), 'failed-precondition', 'driver_inactive');
    assert.strictEqual(await seatsOf(DRIVER), 4);
    assert.strictEqual((await db.collection('intercity_bookings').get()).size, 0);
  });
  await check('S2 qayta verified — bron o\'tadi, o\'rin kamayadi', async () => {
    await capOf('acc_drv', 'verified');
    const r = await book(DRIVER);
    assert.ok(r, 'natija');
    assert.strictEqual(await seatsOf(DRIVER), 3);
  });
  await check('S3 capability\'siz (admin qo\'shgan / eski) e\'lon — bron avvalgidek o\'tadi', async () => {
    const legacy = '998902000031';
    await listing(legacy);
    await book(legacy, OTHER);
    assert.strictEqual(await seatsOf(legacy), 3);
  });
  await check('S4 eski 9 xonali users hujjati orqali suspended — ham rad', async () => {
    const d12 = '998902000032';
    await listing(d12);
    await db.collection('users').doc(d12.slice(3)).set({ role: 'driver', accountId: 'acc_old' });
    await capOf('acc_old', 'suspended');
    await rejectsWith(book(d12, FINANCE), 'failed-precondition', 'driver_inactive');
    assert.strictEqual(await seatsOf(d12), 4);
  });

  // ── M. Admin kirish: telefon + shaxsiy PIN (D-1) ────────────────────
  await reset();
  const signIn = (phone, pin) => fns.adminWebSignIn.run({ phone, ...(pin == null ? {} : { pin }) }, {});
  await check('M1 PIN\'siz kirish — rad (ADMIN_PIN_REQUIRED)', async () => {
    await rejectsWith(signIn(ADMIN), 'invalid-argument', 'ADMIN_PIN_REQUIRED');
  });
  await check('M2 PIN berilmagan admin — umumiy rad (qaysi raqam admin ekani bilinmaydi)', async () => {
    await rejectsWith(signIn(ADMIN, '482915'), 'permission-denied', 'PIN');
  });
  await check('M3 oddiy foydalanuvchi raqami — xuddi shu umumiy rad', async () => {
    await rejectsWith(signIn(OTHER, '482915'), 'permission-denied', 'PIN');
  });
  await check('M4 admin (superadmin emas) boshqaga PIN bera olmaydi', async () => {
    await rejectsWith(fns.adminSetAdminPin.run({ targetPhone: DISPATCHER }, ctxOf(ADMIN)), 'permission-denied');
  });
  await check('M5 panel roli yo\'q foydalanuvchiga PIN berilmaydi', async () => {
    await rejectsWith(fns.adminSetAdminPin.run({ targetPhone: OTHER }, ctxOf(SUPER)),
      'failed-precondition', 'ADMIN_PIN_TARGET_NOT_PANEL_ROLE');
  });
  let adminPinValue = '';
  await check('M6 superadmin PIN beradi: javobda bir marta, serverda faqat xesh, audit', async () => {
    const r = await fns.adminSetAdminPin.run({ targetPhone: ADMIN }, ctxOf(SUPER));
    assert.match(r.pin, /^\d{6}$/);
    adminPinValue = r.pin;
    const cred = (await db.collection('admin_credentials').doc(ADMIN).get()).data();
    assert.ok(!JSON.stringify(cred).includes(r.pin), 'PIN ochiq saqlanmagan');
    assert.strictEqual(cred.mustChange, true);
    const audit = (await db.collection('admin_audit').where('kind', '==', 'admin_pin_set').get()).docs;
    assert.strictEqual(audit.length, 1);
    assert.strictEqual(audit[0].data().actor, SUPER);
  });
  const wrongPin = adminPinValue === '111222' ? '333444' : '111222';
  await check('M7 4 ta noto\'g\'ri PIN — rad; 5-chisi — 15 daqiqa qulf; qulfda to\'g\'ri PIN ham rad', async () => {
    for (let i = 0; i < 4; i += 1) await rejectsWith(signIn(ADMIN, wrongPin), 'permission-denied');
    await rejectsWith(signIn(ADMIN, wrongPin), 'resource-exhausted');
    await rejectsWith(signIn(ADMIN, adminPinValue), 'resource-exhausted');
    const cred = (await db.collection('admin_credentials').doc(ADMIN).get()).data();
    assert.ok(cred.lockedUntil.toMillis() > Date.now() + 14 * 60 * 1000);
  });
  await check('M8 superadmin qayta PIN bersa — qulf ochiladi, yangi PIN bilan kirish (token)', async () => {
    const r = await fns.adminSetAdminPin.run({ targetPhone: ADMIN }, ctxOf(SUPER));
    adminPinValue = r.pin;
    const s = await signIn(ADMIN, adminPinValue);
    assert.ok(typeof s.token === 'string' && s.token.length > 20, 'custom token');
    assert.strictEqual(s.role, 'admin');
    assert.strictEqual(s.mustChangePin, true);
  });
  await check('M9 o\'z PIN\'ini almashtirish: zaif / noto\'g\'ri joriy — rad; to\'g\'ri — eski ishlamaydi', async () => {
    await rejectsWith(fns.adminChangeOwnPin.run({ currentPin: adminPinValue, newPin: '123456' }, ctxOf(ADMIN)),
      'invalid-argument', 'ADMIN_PIN_WEAK');
    await rejectsWith(fns.adminChangeOwnPin.run({ currentPin: wrongPin, newPin: '582913' }, ctxOf(ADMIN)),
      'permission-denied', 'ADMIN_PIN_WRONG');
    await fns.adminChangeOwnPin.run({ currentPin: adminPinValue, newPin: '582913' }, ctxOf(ADMIN));
    await rejectsWith(signIn(ADMIN, adminPinValue), 'permission-denied');
    const s = await signIn(ADMIN, '582913');
    assert.strictEqual(s.mustChangePin, false);
  });
  await check('M10 oddiy foydalanuvchi adminChangeOwnPin chaqira olmaydi', async () => {
    await rejectsWith(fns.adminChangeOwnPin.run({ currentPin: '1', newPin: '582913' }, ctxOf(OTHER)), 'permission-denied');
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} admin-audit CF checks passed.`);
  process.exitCode = failed ? 1 : 0;
  // index.js ichidagi listener/taymerlar jarayonni ushlab qolmasin.
  setTimeout(() => process.exit(process.exitCode), 200);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
