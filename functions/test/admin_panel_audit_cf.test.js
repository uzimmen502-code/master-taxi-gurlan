/**
 * Admin panel ↔ ilova muvofiqlik auditi (2026-10-07/08) — Cloud Functions,
 * HAQIQIY Firestore Emulator + ledger bilan. functions/index.js export'larini
 * `.run(data, context)` orqali chaqiradi.
 *
 *   firebase emulators:exec --only firestore --project demo-admin-audit \
 *     "node functions/test/admin_panel_audit_cf.test.js"
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
    'admin_audit', 'ev_charging_stations', 'support_chats', 'admin_news',
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
