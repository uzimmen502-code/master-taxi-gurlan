/**
 * Ҳамён аудити 2026-10-07 — K-1 (`placeOrderPostPaid`) ва K-6
 * (`creditChange`), ҲАҚИҚИЙ ledger билан (Firestore Emulator, Admin SDK).
 * functions/index.js'даги export'ни `.run(data, context)` орқали чақиради.
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/wallet_order_credit_cf.test.js"
 *
 * K-1: ҳамён эгаси — ФАҚАТ token телефони. Аввал текширув `phone` бўйича,
 *      ечиш эса клиент юборган `userPhone` бўйича эди → бегона ҳамёндан
 *      тўлаш мумкин эди.
 * K-6: `creditChange` — `driver` ролини ҳар ким ўзига ёза олади (rules),
 *      шунинг учун ҳайдовчи бу CF'ни чақира олмаслиги керак; сумма
 *      майдонлари манфий бўлмаган бутун сон.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-audit';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const ledger = require('../settlement_ledger');

const BUYER = '998901000001';
const VICTIM = '998901000002';
const ATTACKER = '998903000001';
const LEGACY9 = '901000009'; // эски 9 хонали `users` ҳужжати
const ADMIN = '998905000001';
const DRIVER = '998902000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

const PLOV_PRICE = 30000;

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
  await Promise.all(['users', 'orders', 'food_catalog', 'food_products',
    'wallet_idempotency', ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  await db.collection('food_catalog').doc('food_plov')
      .set({ name: 'Plov', price: PLOV_PRICE, unit: 'porsiya' });
  await db.collection('users').doc(BUYER).set({ role: 'user', phone: BUYER, bonusBalance: 50000 });
  await db.collection('users').doc(VICTIM).set({ role: 'user', phone: VICTIM, bonusBalance: 200000 });
  await db.collection('users').doc(ATTACKER).set({ role: 'user', phone: ATTACKER, bonusBalance: 0 });
  await db.collection('users').doc(ADMIN).set({ role: 'admin', phone: ADMIN });
  await db.collection('users').doc(DRIVER).set({ role: 'driver', phone: DRIVER });
}
const bal = async (uid) => {
  const s = await db.collection('users').doc(uid).get();
  return s.exists ? (s.data().bonusBalance || 0) : null;
};
const pcBal = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? (s.data().balance || 0) : 0;
};
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
let seq = 0;
const key = () => `test_key_${Date.now()}_${seq++}`;
/** Овқат буюртмаси (сервер нархи `food_catalog`дан). */
function foodOrder(extra = {}) {
  return {
    type: 'food',
    userName: 'Test',
    address: 'Gurlan',
    items: [{ inventoryId: 'food_plov', qty: 1 }],
    useWallet: true,
    balanceApplied: PLOV_PRICE,
    ...extra,
  };
}
const place = (who, data) => fns.placeOrderPostPaid.run(data, ctxOf(who));
const credit = (who, data) => fns.creditChange.run(data, ctxOf(who));
async function rejects(promise, code) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    return;
  }
  throw new Error(`kutilgan ${code}, lekin muvaffaqiyatli bajarildi`);
}

(async () => {
  // ─── K-1: placeOrderPostPaid ────────────────────────────────────────
  await reset();
  await check('A1 o\'z hamyoni bilan buyurtma: o\'z balansi kamayadi, ledger muvozanatda', async () => {
    const r = await place(BUYER, {
      userPhone: BUYER, idempotencyKey: key(), orderBase: foodOrder({ phone: BUYER }),
    });
    assert.strictEqual(r.walletDebit, PLOV_PRICE);
    assert.strictEqual(await bal(BUYER), 50000 - PLOV_PRICE);
    const order = (await db.collection('orders').doc(r.orderId).get()).data();
    assert.strictEqual(order.userPhone, BUYER);
    assert.strictEqual(order.balanceApplied, PLOV_PRICE);
    assert.ok(await journalBalanced() >= 1);
  });

  await reset();
  await check('B1 (K-1) begona userPhone: jabrlanuvchi hamyoniga TEGILMAYDI', async () => {
    const r = await place(ATTACKER, {
      userPhone: VICTIM, idempotencyKey: key(),
      orderBase: foodOrder({ phone: ATTACKER, balanceApplied: 999999999 }),
    });
    assert.strictEqual(await bal(VICTIM), 200000, 'jabrlanuvchi balansi o\'zgarmasligi kerak');
    assert.strictEqual(await pcBal(VICTIM), 0, 'jabrlanuvchi ledger hisobi o\'zgarmasligi kerak');
    assert.strictEqual(r.walletDebit, 0, 'hujumchining o\'z hamyoni bo\'sh — debit 0');
    assert.strictEqual(r.cashDue, PLOV_PRICE);
  });

  await reset();
  await check('B2 (K-1) begona userPhone + o\'z balansi bor: faqat O\'Z hamyoni yechiladi', async () => {
    const r = await place(BUYER, {
      userPhone: VICTIM, idempotencyKey: key(), orderBase: foodOrder({ phone: BUYER }),
    });
    assert.strictEqual(await bal(VICTIM), 200000);
    assert.strictEqual(await bal(BUYER), 50000 - PLOV_PRICE);
    assert.strictEqual(r.walletDebit, PLOV_PRICE);
    assert.strictEqual(await pcBal(BUYER), -PLOV_PRICE, 'ledger: BUYER hisobidan (ochilish yozuvisiz)');
    await journalBalanced();
  });

  await reset();
  await check('B3 userPhone yuborilmasa ham token egasi uchun ishlaydi', async () => {
    const r = await place(BUYER, { idempotencyKey: key(), orderBase: foodOrder({ phone: BUYER }) });
    assert.strictEqual(r.walletDebit, PLOV_PRICE);
    assert.strictEqual(await bal(BUYER), 50000 - PLOV_PRICE);
  });

  await reset();
  await check('B4 eski 9 xonali users hujjati: token 12 xonali bo\'lsa ham shu hamyon', async () => {
    await db.collection('users').doc(LEGACY9).set({ role: 'user', phone: LEGACY9, bonusBalance: 40000 });
    const caller = `998${LEGACY9}`;
    const r = await place(caller, {
      userPhone: caller, idempotencyKey: key(), orderBase: foodOrder({ phone: caller }),
    });
    assert.strictEqual(r.walletDebit, PLOV_PRICE);
    assert.strictEqual(await bal(LEGACY9), 40000 - PLOV_PRICE);
  });

  await reset();
  await check('B5 phone tekshiruvi saqlangan: begona `phone` → permission-denied', async () => {
    await rejects(place(ATTACKER, {
      userPhone: ATTACKER, idempotencyKey: key(), orderBase: foodOrder({ phone: VICTIM }),
    }), 'permission-denied');
    assert.strictEqual(await bal(VICTIM), 200000);
  });

  // ─── K-6: creditChange ──────────────────────────────────────────────
  await reset();
  await check('C1 admin qaytimni hisoblaydi: +delta, ledger muvozanatda', async () => {
    const r = await credit(ADMIN, {
      userPhone: BUYER, orderTotal: 83000, cashPaid: 100000, idempotencyKey: key(),
    });
    assert.strictEqual(r.credited, 17000);
    assert.strictEqual(await bal(BUYER), 50000 + 17000);
    await journalBalanced();
  });

  await reset();
  await check('C2 (K-6) driver roli (o\'ziga yozish mumkin) → permission-denied, pul yo\'q', async () => {
    await rejects(credit(DRIVER, {
      userPhone: DRIVER, orderTotal: 0, cashPaid: 1000000000, idempotencyKey: key(),
    }), 'permission-denied');
    assert.strictEqual(await bal(DRIVER), 0);
    assert.strictEqual(await journalBalanced(), 0);
  });

  await reset();
  await check('C3 (K-6) manfiy orderTotal → invalid-argument (delta sun\'iy oshmaydi)', async () => {
    await rejects(credit(ADMIN, {
      userPhone: BUYER, orderTotal: -500000, cashPaid: 0, idempotencyKey: key(),
    }), 'invalid-argument');
    assert.strictEqual(await bal(BUYER), 50000);
  });

  await reset();
  await check('C4 (K-6) son bo\'lmagan cashPaid → invalid-argument (internal emas)', async () => {
    await rejects(credit(ADMIN, {
      userPhone: BUYER, orderTotal: 1000, cashPaid: 'abc', idempotencyKey: key(),
    }), 'invalid-argument');
    assert.strictEqual(await bal(BUYER), 50000);
  });

  await reset();
  await check('C5 cashPaid < orderTotal → credited 0 (avvalgidek)', async () => {
    const r = await credit(ADMIN, {
      userPhone: BUYER, orderTotal: 5000, cashPaid: 3000, idempotencyKey: key(),
    });
    assert.strictEqual(r.credited, 0);
    assert.strictEqual(await bal(BUYER), 50000);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
