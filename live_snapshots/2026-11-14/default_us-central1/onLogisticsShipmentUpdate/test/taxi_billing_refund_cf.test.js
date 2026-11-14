/**
 * Taxi billing — qaytim kalitlari va parallel amallar (hamyon auditi Y-5, O-13).
 * HAQIQIY ledger bilan (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-taxi-billing \
 *     "node functions/test/taxi_billing_refund_cf.test.js"
 *
 * Y-5: pasaytirishdagi refund va bekor qilishdagi refund BITTA kalitni
 *      (`taxiRefund:{trip}:v{billingVersion}`) ishlatardi → pastga reprice'dan
 *      keyin bekor qilinsa qolgan komissiya QAYTMASDI, reys esa `refunded:true`.
 *      Reys holati tranzaksiyadan tashqarida o'qilardi → parallel cancel/reprice
 *      to'langanidan ko'p qaytarishi mumkin edi.
 * O-13: qarz yopish kaliti soniya-timestamp edi → parallel publish qarzni
 *      ikki marta yechardi.
 *
 * Invariant: har reys uchun  Σ(komissiya) − Σ(qaytim) == trip.feeAmount
 * (published) yoki 0 (bekor qilingan), wallet manfiy emas.
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-taxi-billing';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const { attachTaxiBilling, EARNINGS_ACCOUNT } = require('../taxi_billing');
const caps = require('../capabilities_model');

const DRIVER = '998901110001';
const ACC = 'accDRV000000000000000A';
const NOW0 = new Date('2026-10-06T06:00:00Z');
let clock = NOW0;
/** R7: production'dagi kabi har chaqiruvda soat yuradi (sekund). */
let tick = false;
let tickN = 0;

const digits = (v) => String(v || '').replace(/\D/g, '');
const api = attachTaxiBilling({}, {
  functions, db, admin,
  callerPhone: (ctx) => digits(ctx.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  notifyUserInApp: async () => {},
  now: () => (tick ? new Date(clock.getTime() + (tickN++) * 1000) : clock),
});
const ctx = { auth: { token: { phone_number: `+${DRIVER}` } } };

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
async function reset({ wallet = 100000, debt = 0 } = {}) {
  clock = NOW0;
  await Promise.all(['users', 'provider_capabilities', 'service_agreements', 'module_config',
    'taxi_trips', 'taxi_price_changes', 'taxi_fraud_cases', settlementLedger.COL_JOURNAL,
    settlementLedger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(DRIVER).set({ role: 'user', accountId: ACC, bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC).set({
    identity: { accountId: ACC, primaryUid: DRIVER },
    taxi: { active: true },
    status: { taxi: 'verified' },
    window: { taxi: { billingGraceUntil: null } },
    ...(debt > 0 ? { debt: { taxi: debt } } : {}),
  });
  await db.collection('service_agreements').doc(ACC)
      .set({ taxi: { version: caps.AGREEMENT_VERSIONS.taxi, acceptedAt: NOW0 } });
  if (wallet > 0) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `topup:${DRIVER}:test`, kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: wallet },
        { account: settlementLedger.passengerCreditAccount(DRIVER), cr: wallet }],
    });
  }
}
const pcRef = () => db.collection(settlementLedger.COL_ACCOUNTS)
    .doc(settlementLedger.passengerCreditAccount(DRIVER));
const balance = async () => ((await pcRef().get()).data() || {}).balance || 0;
const earnings = async () => ((await db.collection(settlementLedger.COL_ACCOUNTS)
    .doc(EARNINGS_ACCOUNT).get()).data() || {}).balance || 0;
const trip = async (id) => (await db.collection('taxi_trips').doc(id).get()).data();
const pub = (over = {}) => api.publish({
  farePerSeat: 300000, from: 'Urganch', to: 'Toshkent', scheduleDate: '2026-10-07',
  startTime: '08:00', departureAt: '2026-10-07T03:00:00Z', originLat: 41.55, originLng: 60.63,
  driverLat: 41.55, driverLng: 60.63, ...over,
}, ctx);

/** Reys bo'yicha jurnal: Σ komissiya (earnings cr) − Σ qaytim (earnings dr). */
async function netFee(tripId) {
  const s = await db.collection(settlementLedger.COL_JOURNAL).where('refId', '==', tripId).get();
  let net = 0;
  s.forEach((d) => {
    for (const l of d.data().legs || []) {
      if (l.account === EARNINGS_ACCOUNT) net += (l.cr || 0) - (l.dr || 0);
    }
  });
  return net;
}
/** Parallel chaqiruv: xato bo'lsa ham qolganlari tugaydi. */
const settle = (ps) => Promise.allSettled(ps);

(async () => {
  // ─── Y-5: kalit to'qnashuvi ─────────────────────────────────────────
  await reset();
  await check('R1 pastga reprice → bekor: qolgan komissiya HAM qaytadi (to\'liq qaytim)', async () => {
    const r = await pub(); // fee 24 000 → 76 000
    assert.strictEqual(await balance(), 76000);
    const a = await api.reprice({ tripId: r.tripId, farePerSeat: 250000 }, ctx); // 20 000, refund 4 000
    assert.strictEqual(a.delta, -4000);
    assert.strictEqual(await balance(), 80000);
    const c = await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(c.refunded, true);
    assert.strictEqual(await balance(), 100000, 'komissiya to\'liq qaytishi kerak');
    assert.strictEqual(await earnings(), 0);
    assert.strictEqual(await netFee(r.tripId), 0);
  });

  await reset();
  await check('R2 yuqoriga reprice → bekor: ikkala to\'lov qaytadi', async () => {
    const r = await pub({ farePerSeat: 200000 }); // 16 000
    await api.reprice({ tripId: r.tripId, farePerSeat: 350000 }, ctx); // +12 000 → 28 000
    assert.strictEqual(await balance(), 72000);
    await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(await balance(), 100000);
    assert.strictEqual(await netFee(r.tripId), 0);
  });

  // ─── Y-5: parallel amallar ──────────────────────────────────────────
  await reset();
  await check('R3 ikki parallel cancel → qaytim BIR marta', async () => {
    const r = await pub(); // 24 000
    await settle([api.cancel({ tripId: r.tripId }, ctx), api.cancel({ tripId: r.tripId }, ctx)]);
    assert.strictEqual(await balance(), 100000);
    assert.strictEqual(await netFee(r.tripId), 0);
    assert.strictEqual((await trip(r.tripId)).status, 'cancelled');
  });

  await reset();
  await check('R4 parallel cancel + pastga reprice → jami qaytim to\'langanidan oshmaydi', async () => {
    const r = await pub(); // 24 000
    await settle([
      api.cancel({ tripId: r.tripId }, ctx),
      api.reprice({ tripId: r.tripId, farePerSeat: 250000 }, ctx),
    ]);
    const t = await trip(r.tripId);
    const net = await netFee(r.tripId);
    assert.ok(await balance() <= 100000, `wallet ${await balance()} > 100 000 — ortiqcha qaytim`);
    assert.ok(net >= 0, `earnings manfiy: ${net}`);
    if (t.status === 'cancelled') {
      // Bekor bo'lgan bo'lsa — hammasi qaytgan, ortig'i emas.
      assert.strictEqual(net, 0);
    } else {
      assert.strictEqual(net, t.feeAmount, 'jurnal va reys komissiyasi mos');
    }
  });

  await reset();
  await check('R5 ikki parallel yuqoriga reprice → jurnal == trip.feeAmount', async () => {
    const r = await pub({ farePerSeat: 200000 }); // 16 000
    await settle([
      api.reprice({ tripId: r.tripId, farePerSeat: 300000 }, ctx),
      api.reprice({ tripId: r.tripId, farePerSeat: 400000 }, ctx),
    ]);
    const t = await trip(r.tripId);
    assert.strictEqual(await netFee(r.tripId), t.feeAmount, 'reys komissiyasi jurnalga mos');
    assert.strictEqual(await balance(), 100000 - t.feeAmount);
  });

  await reset();
  await check('R6 cancel qayta chaqiruvi (shu so\'rov) — idempotent, ortiqcha qaytim yo\'q', async () => {
    const r = await pub();
    await api.cancel({ tripId: r.tripId }, ctx);
    const again = await api.cancel({ tripId: r.tripId }, ctx);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await balance(), 100000);
  });

  // ─── O-13: qarz yopish ──────────────────────────────────────────────
  await reset({ wallet: 50000, debt: 4000 });
  await check('R7 ikki parallel publish → qarz BIR marta yechiladi', async () => {
    tick = true;
    try {
      await settle([pub({ farePerSeat: 100000 }), pub({ farePerSeat: 100000 })]);
    } finally {
      tick = false;
    }
    const s = await db.collection(settlementLedger.COL_JOURNAL)
        .where('kind', '==', 'taxi_fee_debt_settlement').get();
    assert.strictEqual(s.size, 1, `qarz ${s.size} marta yechildi`);
    const cap = (await db.collection('provider_capabilities').doc(ACC).get()).data();
    assert.strictEqual(cap.debt.taxi, 0);
    assert.ok(await balance() >= 0);
  });

  await reset({ wallet: 50000, debt: 4000 });
  await check('R8 qarz yopilgach yangi qarz: ikkinchi raund ham yechiladi (kalit qayta ishlatilmaydi)', async () => {
    await pub({ farePerSeat: 100000 }); // qarz 4 000 + fee 8 000
    await db.collection('provider_capabilities').doc(ACC).set({ debt: { taxi: 3000 } }, { merge: true });
    await pub({ farePerSeat: 100000 }); // yangi qarz 3 000 + fee 8 000
    const s = await db.collection(settlementLedger.COL_JOURNAL)
        .where('kind', '==', 'taxi_fee_debt_settlement').get();
    assert.strictEqual(s.size, 2);
    assert.strictEqual(await balance(), 50000 - 4000 - 8000 - 3000 - 8000);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
