/**
 * Mahalliy taksi — `completeLocalTrip` callable, HAQIQIY ledger bilan
 * (Firestore Emulator, Admin SDK). functions/index.js'dagi export'ni
 * to'g'ridan-to'g'ri `.run(data, context)` orqali chaqiradi.
 *
 *   firebase emulators:exec --only firestore --project demo-local-taxi \
 *     "node functions/test/local_taxi_complete_cf.test.js"
 *
 * A — mavjud xatti-harakat (ishlashi SHART).
 * B — ega qarorlari 2026-10-07: hamyon → haydovchi hamyoni, faqat server
 *     narxi bilan hamyon yechiladi, natija faqat biriktirilgan haydovchiga.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-local-taxi';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const ledger = require('../settlement_ledger');

const PASSENGER = '998901000001';
const VICTIM = '998901000002';
const DRIVER = '998902000001';
const STRANGER = '998903000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const complete = (data, who = DRIVER) => fns.completeLocalTrip.run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset() {
  await Promise.all(['users', 'trips', 'drivers', 'wallet_idempotency',
    ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(PASSENGER).set({ role: 'user', bonusBalance: 50000 });
  await db.collection('users').doc(VICTIM).set({ role: 'user', bonusBalance: 200000 });
  await db.collection('users').doc(DRIVER).set({ role: 'user' });
}
/** Server narxi bilan yaratilgan trip (createLocalTaxiTrip). */
function trip(extra = {}) {
  return {
    userPhone: PASSENGER, fromAddr: 'A', status: 'accepted', taxiType: 'local',
    acceptedDriverId: DRIVER, driverId: DRIVER, fareSource: 'server', tariffVersion: 1,
    ...extra,
  };
}
/** Eski ilova yaratgan trip (server narxisiz). */
function legacyTrip(extra = {}) {
  const t = trip(extra);
  delete t.fareSource;
  delete t.tariffVersion;
  return t;
}
const bal = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance;
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

async function main() {
  // ── A. Mavjud xatti-harakat ──────────────────────────────────────────
  await reset();
  await db.collection('trips').doc('t1').set(trip({ lockedFare: 15000, passengerWalletIntent: 5000 }));
  await check('A1 lockedFare=15000, hamyon 5000, naqd 10000 → walletPaid 5000, change 0, completed', async () => {
    const r = await complete({ tripId: 't1', fare: 99999, cashPaid: 10000 });
    assert.strictEqual(r.fare, 15000, 'client fare e\'tiborsiz, lockedFare ishlatiladi');
    assert.strictEqual(r.walletPaid, 5000);
    assert.strictEqual(r.cashDue, 10000);
    assert.strictEqual(r.change, 0);
    assert.strictEqual(await bal(PASSENGER), 45000);
    const t = (await db.collection('trips').doc('t1').get()).data();
    assert.strictEqual(t.status, 'completed');
    assert.strictEqual((await db.collection('drivers').doc(DRIVER).get()).data().isBusy, false);
  });
  await check('A2 qayta chaqiruv (retry) — hamyon IKKINCHI marta yechilmaydi', async () => {
    const r = await complete({ tripId: 't1', fare: 15000, cashPaid: 10000 });
    assert.strictEqual(r.walletPaid, 5000);
    assert.strictEqual(await bal(PASSENGER), 45000);
  });
  await check('A3 ledger Σdr == Σcr va bitta bonus journal', async () => {
    assert.strictEqual(await journalBalanced(), 1);
  });
  await check('A4 naqd ortiqcha: fare 15000, naqd 20000, hamyonsiz → change 5000', async () => {
    await db.collection('trips').doc('t2').set(trip({ lockedFare: 15000 }));
    const r = await complete({ tripId: 't2', cashPaid: 20000 });
    assert.strictEqual(r.change, 5000);
    assert.strictEqual(r.walletPaid, 0);
  });
  await check('A5 begona haydovchi yakunlay olmaydi', async () => {
    await db.collection('trips').doc('t3').set(trip({ lockedFare: 15000 }));
    await assert.rejects(complete({ tripId: 't3', cashPaid: 15000 }, STRANGER), /biriktirilmagan/);
  });
  await check('A6 searching (qabul qilinmagan) trip yakunlanmaydi', async () => {
    await db.collection('trips').doc('t4').set(trip({ status: 'searching', lockedFare: 15000 }));
    await assert.rejects(complete({ tripId: 't4', cashPaid: 15000 }), /holati/);
  });
  await check('A7 bekor qilingan trip yakunlanmaydi', async () => {
    await db.collection('trips').doc('t5').set(trip({ status: 'cancelled', lockedFare: 15000 }));
    await assert.rejects(complete({ tripId: 't5', cashPaid: 15000 }), /holati/);
  });
  await check('A8 hamyon intent > balans → faqat balans yechiladi, manfiy yo\'q', async () => {
    await db.collection('users').doc(PASSENGER).set({ bonusBalance: 3000 }, { merge: true });
    await db.collection('trips').doc('t6').set(trip({ lockedFare: 15000, passengerWalletIntent: 15000 }));
    const r = await complete({ tripId: 't6', cashPaid: 12000 });
    assert.strictEqual(r.walletPaid, 3000);
    assert.strictEqual(await bal(PASSENGER), 0);
  });
  await check('A9 manfiy cashPaid rad etiladi', async () => {
    await db.collection('trips').doc('t7').set(trip({ lockedFare: 15000 }));
    await assert.rejects(complete({ tripId: 't7', cashPaid: -5 }), /cashPaid/);
  });

  // ── B. Talablar (FAIL = nuqson) ─────────────────────────────────────
  await reset();
  await db.collection('trips').doc('b1').set(trip({ lockedFare: 15000, passengerWalletIntent: 15000 }));
  await check('B1 yo\'lovchi hamyondan to\'lagan 15000 HAYDOVCHI HAMYONIGA tushadi (ega qarori 2026-10-07)', async () => {
    await complete({ tripId: 'b1', cashPaid: 0 });
    const legs = (await db.collection(ledger.COL_JOURNAL).get()).docs.flatMap((d) => d.data().legs || []);
    const toDriver = legs.filter((l) => l.account === `passenger_credit:${DRIVER}`)
      .reduce((a, l) => a + (l.cr || 0) - (l.dr || 0), 0);
    assert.strictEqual(toDriver, 15000, `pul hisoblari: ${JSON.stringify(legs)}`);
    assert.ok(!legs.some((l) => l.account === 'admin_clearing'), 'admin_clearing ishlatilmasin');
  });
  await check('B1b yo\'lovchi balansi 15000 ga kamaydi, haydovchi users.bonusBalance +15000, ledger muvozanatda', async () => {
    assert.strictEqual(await bal(PASSENGER), 35000);
    assert.strictEqual(await bal(DRIVER), 15000);
    await journalBalanced();
    const pcDriver = (await db.collection(ledger.COL_ACCOUNTS).doc(`passenger_credit:${DRIVER}`).get()).data();
    assert.strictEqual(pcDriver.balance, 15000);
  });
  await check('B1c retry — haydovchiga IKKINCHI marta kredit yo\'q', async () => {
    await complete({ tripId: 'b1', cashPaid: 0 });
    assert.strictEqual(await bal(DRIVER), 15000);
    assert.strictEqual(await bal(PASSENGER), 35000);
  });
  await check('B2 server narxi bor trip: haydovchi yuborgan fare (999 999 999) e\'tiborsiz', async () => {
    await db.collection('trips').doc('b2').set(trip({ lockedFare: 12000 }));
    const r = await complete({ tripId: 'b2', fare: 999999999, cashPaid: 12000 });
    assert.strictEqual(r.fare, 12000);
  });
  await check('B2b server narxli trip lockedFare\'siz — yakunlanmaydi (klient narxiga o\'tilmaydi)', async () => {
    await db.collection('trips').doc('b2b').set(trip({}));
    await assert.rejects(complete({ tripId: 'b2b', fare: 50000, cashPaid: 50000 }), /lockedFare/);
  });
  await check('B3 eski (server narxisiz) trip: hamyon intent bo\'lsa ham hamyon YECHILMAYDI', async () => {
    await db.collection('trips').doc('b3').set(legacyTrip({
      userPhone: VICTIM, lockedFare: 200000, passengerWalletIntent: 200000,
    }));
    const r = await complete({ tripId: 'b3', cashPaid: 0 });
    assert.strictEqual(r.walletPaid, 0);
    assert.strictEqual(await bal(VICTIM), 200000, `VICTIM balansi ${await bal(VICTIM)} ga tushdi`);
  });
  await check('B3b eski trip: haydovchi narxi bilan naqd yakunlanadi (orqaga moslik)', async () => {
    await db.collection('trips').doc('b3b').set(legacyTrip({}));
    const r = await complete({ tripId: 'b3b', fare: 9000, cashPaid: 10000 });
    assert.strictEqual(r.fare, 9000);
    assert.strictEqual(r.change, 1000);
  });
  await check('B4 yakunlangan trip natijasi begona chaqiruvchiga qaytarilmaydi', async () => {
    await assert.rejects(complete({ tripId: 'b1', cashPaid: 0 }, STRANGER), /biriktirilmagan/);
  });
  await check('B5 yo\'lovchi = haydovchi (o\'z-o\'ziga) — hamyon ko\'chmaydi', async () => {
    await db.collection('users').doc(DRIVER).set({ bonusBalance: 15000 }, { merge: true });
    await db.collection('trips').doc('b5').set(trip({
      userPhone: DRIVER, lockedFare: 10000, passengerWalletIntent: 10000,
    }));
    const r = await complete({ tripId: 'b5', cashPaid: 10000 });
    assert.strictEqual(r.walletPaid, 0);
    assert.strictEqual(await bal(DRIVER), 15000);
  });

  // ── C. expirePendingTrips — haydovchi tark etgan trip darhol o'lmasin ──
  const T = admin.firestore.Timestamp;
  const nowMs = Date.now();
  await db.collection('trips').doc('e1').set(legacyTrip({
    status: 'searching', acceptedDriverId: '', driverId: '',
    expiresAt: T.fromMillis(nowMs - 5 * 60000), releasedAt: T.fromMillis(nowMs - 60000),
  }));
  await db.collection('trips').doc('e2').set(legacyTrip({
    status: 'searching', acceptedDriverId: '', driverId: '',
    expiresAt: T.fromMillis(nowMs - 60000),
  }));
  await db.collection('trips').doc('e3').set(legacyTrip({
    status: 'searching', acceptedDriverId: '', driverId: '',
    expiresAt: T.fromMillis(nowMs - 10 * 60000), releasedAt: T.fromMillis(nowMs - 4 * 60000),
  }));
  await fns.expirePendingTrips.run({});
  await check('C1 release\'dan 1 daqiqa o\'tgan trip — searching qoladi, expiresAt = releasedAt+3m', async () => {
    const t = (await db.collection('trips').doc('e1').get()).data();
    assert.strictEqual(t.status, 'searching');
    assert.strictEqual(t.expiresAt.toMillis(), nowMs - 60000 + 180000);
  });
  await check('C2 oddiy muddati o\'tgan trip — expired (avvalgidek)', async () => {
    assert.strictEqual((await db.collection('trips').doc('e2').get()).data().status, 'expired');
  });
  await check('C3 release\'dan 4 daqiqa o\'tgan trip — expired', async () => {
    assert.strictEqual((await db.collection('trips').doc('e3').get()).data().status, 'expired');
  });

  // ── D. onTripUpdate — accepted'dan har qanday chiqishda isBusy=false ───
  const snapOf = (id, data) => ({ id, data: () => data, ref: db.collection('trips').doc(id) });
  const fire = (id, before, after) => fns.onTripUpdate.run(
      { before: snapOf(id, before), after: snapOf(id, after) }, { params: { tripId: id } });
  await wipe('trips'); // oldingi bo'limlardagi accepted trip'lar
  await db.collection('drivers').doc(DRIVER).set({ isBusy: true });
  await check('D1 admin bekor qilsa ham haydovchi bo\'shatiladi', async () => {
    const before = trip({ lockedFare: 1000 });
    await fire('d1', before, { ...before, status: 'cancelled', cancelledBy: 'admin' });
    assert.strictEqual((await db.collection('drivers').doc(DRIVER).get()).data().isBusy, false);
  });
  await check('D2 haydovchi boshqa safarda bo\'lsa — isBusy tegilmaydi', async () => {
    await db.collection('drivers').doc(DRIVER).set({ isBusy: true });
    await db.collection('trips').doc('d2other').set(trip({ lockedFare: 1000 }));
    const before = trip({ lockedFare: 1000 });
    await fire('d2', before, { ...before, status: 'expired' });
    assert.strictEqual((await db.collection('drivers').doc(DRIVER).get()).data().isBusy, true);
  });

  const failed = results.filter((p) => !p).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
