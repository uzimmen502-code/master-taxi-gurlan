/**
 * Ҳамён инвариантлари кунлик текшируви — `wallet_invariants.js` (Firestore Emulator, ҲАҚИҚИЙ ledger).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-inv \
 *     "node functions/test/wallet_invariants_cf.test.js"
 *
 * Қулфланади: тоза ҳолатда ok; I-1 (ортиқча bonusBalance, ҳисобсиз bonusBalance, userсиз ҳисоб), I-2 (мувозанатсиз
 * ёзув, журналга тенг бўлмаган ҳисоб, номаълум ҳисоб), I-3 (базадан кейинги тарих), I-3F (тўлиқ тарих), аномалиялар
 * (манфий, бутун эмас); белги қоидаси (debitCredit 'debit', order_payment_*); ҳисобот ҳужжати, имзо бўйича хабар
 * такрорланмаслиги, текширув ҳеч нарсани ТУЗАТМАСЛИГИ; саҳифалаш (pageSize 2); scheduled функция index.js'да.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-inv';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const inv = require('../wallet_invariants');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;
const PRE = TS.fromDate(new Date('2026-06-01T00:00:00Z'));
const A = '998930000001';
const B = '998930000002';
const C = '998930000003';

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const wl = (uid) => db.collection('users').doc(uid).collection('wallet_ledger');
async function credit(uid, amount, key, type = 'test_credit') {
  await ledger.postEntry(db, {
    idempotencyKey: key, kind: 'test', legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  }, { mirrorBonus: true, walletLedgerType: type });
}
async function debit(uid, amount, key, row) {
  await ledger.postEntry(db, {
    idempotencyKey: key, kind: 'test', legs: [{ account: ledger.passengerCreditAccount(uid), dr: amount }, { account: 'admin_clearing', cr: amount }],
  }, { mirrorBonus: true });
  await wl(uid).add({ ...row, createdAt: admin.firestore.FieldValue.serverTimestamp() });
}
/** Тоза ҳолат: A — базагача тарих 10 000 + opening 10 000, кейин +5 000, realty −2 000 (debitCredit), маҳсулот тўлови. */
async function seedClean() {
  await clearEmulator();
  await db.collection('users').doc(A).set({ phone: A });
  await wl(A).add({ type: 'change_accrued', amount: 10000, createdAt: PRE });
  await db.collection('users').doc(A).set({ bonusBalance: 10000 }, { merge: true });
  await ledger.postEntry(db, {
    idempotencyKey: `opening:${A}`, kind: 'opening_balance',
    legs: [{ account: 'admin_clearing', dr: 10000 }, { account: ledger.passengerCreditAccount(A), cr: 10000 }],
  }, { mirrorBonus: false });
  await credit(A, 5000, 'c1');
  await debit(A, 2000, 'd1', { type: 'realty_tier_purchase', amount: 2000, debitCredit: 'debit' });
  await wl(A).add({ type: 'order_payment_product', amount: 7777, meta: { debitCredit: 'none' }, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  await wl(A).add({ type: 'order_payment_cash', amount: 0, meta: { debitCredit: 'debit' }, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  await db.collection('users').doc(B).set({ phone: B });
  await credit(B, 3000, 'c2');
}
const run = (extra = {}) => inv.runWalletInvariantCheck({ db, admin, log: { log() {}, error() {} }, ...extra });

(async () => {
  await check('W0 scheduled funksiya index.js ga ulangan', async () => {
    assert.ok(fns.walletInvariantDailyCheck, 'walletInvariantDailyCheck export yo\'q');
  });

  await seedClean();
  await check('W1 toza holat: barcha invariantlar OK, xabar yo\'q, hisobot yoziladi', async () => {
    const sent = [];
    const r = await run({ notify: async (x) => { sent.push(x); return { notified: 1 }; } });
    assert.strictEqual(r.ok, true, JSON.stringify(r.invariants));
    assert.strictEqual(r.wallets, 2);
    assert.strictEqual(sent.length, 0);
    const doc = await db.collection(inv.REPORT_COLLECTION).doc(r.date).get();
    assert.ok(doc.exists);
    assert.strictEqual(doc.data().ok, true);
    assert.strictEqual(doc.data().signature, 'ok');
  });

  await check('W2 sahifalash (pageSize 2) bir xil natija', async () => {
    const r = await run({ pageSize: 2, writeReport: false });
    assert.strictEqual(r.ok, true, JSON.stringify(r.invariants));
    assert.strictEqual(r.entryCount, 4); // opening, c1, d1, c2
  });

  await check('W3 ledger\'siz bonusBalance (+500): I-1 va I-3 drift, xabar 1 marta, qayta ishga tushsa takrorlanmaydi', async () => {
    await db.collection('users').doc(B).update({ bonusBalance: admin.firestore.FieldValue.increment(500) });
    const sent = [];
    const notify = async (x) => { sent.push(x); return { notified: 2 }; };
    const r = await run({ notify });
    assert.strictEqual(r.ok, false);
    assert.deepStrictEqual(r.invariants.I1.mismatches.map((m) => [m.uid, m.diff]), [[B, 500]]);
    assert.strictEqual(r.invariants.I3.mismatchCount, 1);
    assert.strictEqual(r.invariants.I3F.mismatchCount, 1);
    assert.strictEqual(r.invariants.I2.ok, true);
    assert.strictEqual(sent.length, 1);
    assert.ok(/I-1/.test(sent[0].text));
    await run({ notify });
    assert.strictEqual(sent.length, 1, 'bir xil imzo — qayta xabar yo\'q');
    const doc = (await db.collection(inv.REPORT_COLLECTION).doc(r.date).get()).data();
    assert.strictEqual(doc.runs, 3, 'W1 + W3 dagi 2 ta ishga tushirish');
    assert.strictEqual(doc.notifiedSignature, r.signature);
  });

  await check('W4 tekshiruv hech narsani tuzatmaydi (bonusBalance, hisob, jurnal o\'zgarmaydi)', async () => {
    const before = [(await db.collection('users').doc(B).get()).data().bonusBalance,
      (await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(B)).get()).data().balance,
      (await db.collection(ledger.COL_JOURNAL).get()).size];
    await run({ writeReport: false });
    const after = [(await db.collection('users').doc(B).get()).data().bonusBalance,
      (await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(B)).get()).data().balance,
      (await db.collection(ledger.COL_JOURNAL).get()).size];
    assert.deepStrictEqual(after, before);
  });

  await seedClean();
  await check('W5 hisobsiz bonusBalance (C) va user\'siz hisob: I-1 ikkalasini ko\'radi', async () => {
    await db.collection('users').doc(C).set({ bonusBalance: 700 });
    await credit('998930000099', 400, 'ghost');
    await db.collection('users').doc('998930000099').delete();
    const r = await run({ writeReport: false });
    const m = Object.fromEntries(r.invariants.I1.mismatches.map((x) => [x.uid, x]));
    assert.strictEqual(m[C].hasAccount, false);
    assert.strictEqual(m[C].diff, 700);
    assert.strictEqual(m['998930000099'].diff, -400);
    assert.ok(r.invariants.anomalies.items.some((a) => a.kind === 'ledger_without_user'));
  });

  await seedClean();
  await check('W6 I-2: muvozanatsiz yozuv, jurnalga teng bo\'lmagan hisob, noma\'lum hisob', async () => {
    await db.collection(ledger.COL_JOURNAL).doc('bad1').set({ legs: [{ account: 'admin_cash', dr: 100 }, { account: 'admin_clearing', cr: 90 }] });
    await db.collection(ledger.COL_JOURNAL).doc('bad2').set({ legs: [{ account: 'mystery:1', dr: 5 }, { account: 'admin_clearing', cr: 5 }] });
    await db.collection(ledger.COL_ACCOUNTS).doc('admin_cash').set({ type: 'asset', balance: 1 });
    const r = await run({ writeReport: false });
    assert.strictEqual(r.invariants.I2.ok, false);
    const errs = r.invariants.I2.entryErrors.map((e) => `${e.id}:${e.error}`).sort();
    assert.deepStrictEqual(errs, ['bad1:unbalanced', 'bad2:unknown_account']);
    assert.ok(r.invariants.I2.accountMismatches.some((a) => a.account === 'admin_cash' && a.problem === 'balance_ne_journal'));
  });

  await seedClean();
  await check('W7 I-3F: baza oldidagi tarix opening\'dan farq qilsa faqat I-3F (I-1/I-3 OK)', async () => {
    await wl(A).add({ type: 'purchase_debit', amount: -1500, createdAt: PRE });
    const r = await run({ writeReport: false });
    assert.strictEqual(r.invariants.I1.ok, true);
    assert.strictEqual(r.invariants.I3.ok, true);
    assert.deepStrictEqual(r.invariants.I3F.mismatches.map((m) => [m.uid, m.diff]), [[A, 1500]]);
  });

  await seedClean();
  await check('W8 anomaliyalar: manfiy va butun bo\'lmagan qiymat, createdAt\'siz qator', async () => {
    await db.collection('users').doc(C).set({ bonusBalance: -50 });
    await wl(A).add({ type: 'x', amount: 1.5, createdAt: PRE });
    await wl(B).add({ type: 'y', amount: 0 });
    const r = await run({ writeReport: false });
    const kinds = r.invariants.anomalies.items.map((a) => a.kind).sort();
    assert.deepStrictEqual(kinds, ['negative_bonus', 'non_integer_wallet_row', 'wallet_row_without_createdAt']);
  });

  await check('W9 belgi qoidasi (sof)', async () => {
    assert.strictEqual(inv.walletRowEffect({ type: 'realty_tier_purchase', amount: 2000, debitCredit: 'debit' }), -2000);
    assert.strictEqual(inv.walletRowEffect({ type: 'purchase_debit', amount: -300 }), -300);
    assert.strictEqual(inv.walletRowEffect({ type: 'order_payment_product', amount: 900 }), 0);
    assert.strictEqual(inv.walletRowEffect({ type: 'x', amount: 2.5 }), null);
    assert.strictEqual(inv.tashkentDate(Date.parse('2026-11-27T20:30:00Z')), '2026-11-28');
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
