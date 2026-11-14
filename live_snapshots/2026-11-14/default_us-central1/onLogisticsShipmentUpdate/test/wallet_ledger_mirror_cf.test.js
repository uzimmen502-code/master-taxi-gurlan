/**
 * Ҳамён аудити Y-1: TV реклама ва Кўчмас мулк харидлари ledger кўзгуси
 * билан (Firestore Emulator, Admin SDK, ҲАҚИҚИЙ ledger).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/wallet_ledger_mirror_cf.test.js"
 *
 * Аввал `publishTvAd`, `renewTvAd`, `purchaseRealtyTier/Package/ProPackage`
 * фақат `users.bonusBalance`ни камайтирарди, `passenger_credit` эса
 * камаймасди → ledger'га қарайдиган ечиш/settlement сарфланган пулни яна
 * ишлатишга йўл берарди. Инвариант: ҳар хариддан кейин
 * passenger_credit:{uid}.balance == users/{uid}.bonusBalance, журнал Σdr==Σcr.
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
const POOR = '998901000009';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const START = 500000;
const PRICE = { tv: 20000, tier: 25000, pkg: 30000, pro: 40000 };

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
  await Promise.all(['users', 'settings', 'tv_clips', 'realty_listings', 'wallet_idempotency',
    ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  await db.doc('settings/app').set({
    tvAdPricing: { basic: { 7: PRICE.tv } },
    realtyPricing: { promo: { 7: PRICE.tier } },
    realtyPackagePricing: { 5: PRICE.pkg },
    realtyProPlans: [{ id: 'pro1', objects: 5, days: 30, price: PRICE.pro }],
  });
  for (const [uid, bal] of [[BUYER, START], [POOR, 1000]]) {
    await db.collection('users').doc(uid).set({
      role: 'user', phone: uid, bonusBalance: bal, realtyOwnerKey: `key_${uid}`,
    });
    // Проекция мос ҳолатдан бошланади (opening balance мигрaцияси каби).
    await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid))
        .set({ type: 'liability', ownerUid: uid, balance: bal });
  }
  await db.collection('realty_listings').doc('L1')
      .set({ ownerKey: `key_${BUYER}`, tier: 'plain', status: 'active' });
  await db.collection('tv_clips').doc('C1').set({
    category: 'ad', ownerPhone: BUYER, adScope: 'district', status: 'active',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000),
  });
}
const bal = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance;
const pc = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? s.data().balance : 0;
};
async function journal() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((a, l) => a + (l.dr || 0), 0);
    const cr = legs.reduce((a, l) => a + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id} Σdr ${dr} != Σcr ${cr}`);
  }
  return s.docs.map((d) => d.data());
}
async function assertMirrored(uid, expected, kind) {
  assert.strictEqual(await bal(uid), expected, 'bonusBalance');
  assert.strictEqual(await pc(uid), expected, 'passenger_credit == bonusBalance');
  const entries = await journal();
  if (kind) {
    const e = entries.find((x) => x.kind === kind);
    assert.ok(e, `journal kind ${kind} topilmadi`);
    assert.ok(e.legs.some((l) => l.account === ledger.passengerCreditAccount(uid) && l.dr > 0));
  }
}
async function rejects(promise, code) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    return;
  }
  throw new Error(`kutilgan ${code}, lekin muvaffaqiyatli bajarildi`);
}

(async () => {
  await reset();
  await check('M1 publishTvAd: bonusBalance va ledger birga kamayadi', async () => {
    await fns.publishTvAd.run({
      idempotencyKey: 'k_pub_1', durationDays: 7, tier: 'basic', scope: 'district',
      videoUrl: 'https://x/v.m3u8', title: 'Test',
    }, ctxOf(BUYER));
    await assertMirrored(BUYER, START - PRICE.tv, 'tv_ad_purchase');
  });

  await reset();
  await check('M2 publishTvAd qayta chaqiruv (shu kalit) — ikkinchi marta yechilmaydi', async () => {
    const data = {
      idempotencyKey: 'k_pub_2', durationDays: 7, tier: 'basic', scope: 'district',
      videoUrl: 'https://x/v.m3u8', title: 'Test',
    };
    await fns.publishTvAd.run(data, ctxOf(BUYER));
    await fns.publishTvAd.run(data, ctxOf(BUYER));
    await assertMirrored(BUYER, START - PRICE.tv);
    assert.strictEqual((await journal()).length, 1);
  });

  await reset();
  await check('M3 renewTvAd: ledger ko\'zgusi', async () => {
    await fns.renewTvAd.run({
      idempotencyKey: 'k_ren_1', clipId: 'C1', durationDays: 7, tier: 'basic',
    }, ctxOf(BUYER));
    await assertMirrored(BUYER, START - PRICE.tv, 'tv_ad_renew');
  });

  await reset();
  await check('M4 purchaseRealtyTier: ledger ko\'zgusi', async () => {
    await fns.purchaseRealtyTier.run({
      idempotencyKey: 'k_tier_1', listingId: 'L1', tier: 'promo', durationDays: 7,
    }, ctxOf(BUYER));
    await assertMirrored(BUYER, START - PRICE.tier, 'realty_tier_purchase');
  });

  await reset();
  await check('M5 purchaseRealtyPackage: ledger ko\'zgusi', async () => {
    await fns.purchaseRealtyPackage.run({ idempotencyKey: 'k_pkg_1', size: 5 }, ctxOf(BUYER));
    await assertMirrored(BUYER, START - PRICE.pkg, 'realty_package_purchase');
  });

  await reset();
  await check('M6 purchaseRealtyProPackage: ledger ko\'zgusi', async () => {
    await fns.purchaseRealtyProPackage.run({ idempotencyKey: 'k_pro_1', planId: 'pro1' }, ctxOf(BUYER));
    await assertMirrored(BUYER, START - PRICE.pro, 'realty_pro_purchase');
  });

  await reset();
  await check('M7 ketma-ket 5 xarid: oxirida ham passenger_credit == bonusBalance', async () => {
    await fns.publishTvAd.run({
      idempotencyKey: 'k_all_1', durationDays: 7, tier: 'basic', scope: 'district',
      videoUrl: 'https://x/v.m3u8', title: 'T',
    }, ctxOf(BUYER));
    await fns.renewTvAd.run({ idempotencyKey: 'k_all_2', clipId: 'C1', durationDays: 7, tier: 'basic' }, ctxOf(BUYER));
    await fns.purchaseRealtyTier.run({ idempotencyKey: 'k_all_3', listingId: 'L1', tier: 'promo', durationDays: 7 }, ctxOf(BUYER));
    await fns.purchaseRealtyPackage.run({ idempotencyKey: 'k_all_4', size: 5 }, ctxOf(BUYER));
    await fns.purchaseRealtyProPackage.run({ idempotencyKey: 'k_all_5', planId: 'pro1' }, ctxOf(BUYER));
    const spent = PRICE.tv * 2 + PRICE.tier + PRICE.pkg + PRICE.pro;
    await assertMirrored(BUYER, START - spent);
    assert.strictEqual((await journal()).length, 5);
  });

  await reset();
  await check('M8 balans yetmasa — hech narsa yozilmaydi (bonusBalance ham, ledger ham)', async () => {
    await rejects(fns.purchaseRealtyPackage.run({ idempotencyKey: 'k_poor', size: 5 }, ctxOf(POOR)),
        'failed-precondition');
    await assertMirrored(POOR, 1000);
    assert.strictEqual((await journal()).length, 0);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
