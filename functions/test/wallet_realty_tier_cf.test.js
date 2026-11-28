/**
 * purchaseRealtyTier — walletPost орқали ҲАҚИҚИЙ ledger билан (W-1). realty_submit_cf бу йўлни қопламайди,
 * realty_expiry эса ledger stub ишлатади — шу сабаб алоҳида.
 *
 *   firebase emulators:exec --only firestore --project demo-realty-tier \
 *     "node functions/test/wallet_realty_tier_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-realty-tier';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const crypto = require('crypto');
const fns = require('../index.js');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const inv = require('../wallet_invariants');

const db = admin.firestore();
const A = '998901120001';
const ctx = (p) => ({ auth: { uid: p, token: { phone_number: `+${p}` } } });
const call = (name, data, p) => fns[name].run(data, ctx(p));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

(async () => {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error('emulator clear');
  await db.doc(`users/${A}`).set({ name: 'Али' });
  await ledger.postEntry(db, {
    idempotencyKey: 'topup:A', kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: 500000 }, { account: ledger.passengerCreditAccount(A), cr: 500000 }],
  }, { mirrorBonus: true, walletLedgerType: 'test_topup' });

  await check('T1 SROCHNO 3 kun: bonusBalance −narx, wallet_ledger (musbat + debit), jurnal realty_tier_purchase', async () => {
    const r = await call('submitRealtyListing', {
      deal: 'sale', title: 'Уч хонали уй', text: 'Тавсиф матни', lat: 41.844, lng: 60.392,
      addressText: 'Гурлан, Навоий кўчаси 12', contactMode: 'owner', tier: 'plain', imageUrls: [], idempotencyKey: crypto.randomUUID(),
    }, A);
    await call('purchaseRealtyTier', { idempotencyKey: crypto.randomUUID(), listingId: r.listingId, tier: 'urgent', durationDays: 3 }, A);
    const bal = (await db.doc(`users/${A}`).get()).data().bonusBalance;
    const price = 500000 - bal;
    assert.ok(price > 0, `narx > 0 (${price})`);
    const rows = (await db.collection(`users/${A}/wallet_ledger`).where('type', '==', 'realty_tier_purchase').get()).docs.map((d) => d.data());
    assert.strictEqual(rows.length, 1);
    assert.strictEqual(rows[0].amount, price);
    assert.strictEqual(rows[0].debitCredit, 'debit');
    assert.strictEqual(rows[0].refType, 'realty_listing');
    assert.strictEqual(rows[0].refId, r.listingId);
    const j = (await db.collection(ledger.COL_JOURNAL).where('kind', '==', 'realty_tier_purchase').get()).docs;
    assert.strictEqual(j.length, 1);
    assert.strictEqual(j[0].data().amount, price);
    assert.ok(j[0].id.startsWith('bonus:realty_'));
  });

  await check('T2 hamma omborlar mos (I-1/I-2/I-3/I-3F yashil)', async () => {
    const rep = inv.evaluate(await inv.collectState(db));
    assert.strictEqual(rep.ok, true, JSON.stringify(rep.invariants));
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(results.length - passed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
