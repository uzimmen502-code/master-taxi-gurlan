/**
 * F-1 (takrorlanishlar auditi 2026-11-28, ega 2026-11-28): eski «Аралаш» e'lonlari (`ads`, cheap_product).
 * `onAdUpdate` — qayta joylashtirish (`inactive → pending`) qaytariladi, muddat (`expiresAt`) uzaymaydi;
 * yashirish / admin yozuvi — avvalgidek. (`submitMarketAd` — module_gate_cf M*, `renewMarketListing` — market_moderation_cf R3.)
 *
 *   firebase emulators:exec --only firestore --project demo-market-ad-retired "node test/market_ad_retired_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-market-ad-retired';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const retired = require('../market_ad_retired');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;
const OWNER = '998917100001';

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
const EXP = TS.fromMillis(Date.now() + 5 * 86400000);
const seed = (id, extra) => db.collection('ads').doc(id).set({
  type: 'cheap_product', ownerId: OWNER, phone: OWNER, title: 'Velosiped', description: 'Yaxshi',
  price: 350000, imageUrls: ['https://x/ads%2F1.jpg'], status: 'active',
  moderatedAt: TS.fromMillis(1000), expiresAt: EXP, ...extra,
});
/** Bitta yozuv + trigger; trigger o'z yozuvi qayta triggerni ham bir marta yuritadi. */
async function runUpdate(id, patch) {
  const ref = db.collection('ads').doc(id);
  const before = await ref.get();
  await ref.update(patch);
  const after = await ref.get();
  await fns.onAdUpdate.run({ before, after }, { params: { adId: id } });
  const after2 = await ref.get();
  if (JSON.stringify(after2.data().status) !== JSON.stringify(after.data().status)) {
    await fns.onAdUpdate.run({ before: after, after: after2 }, { params: { adId: id } });
  }
  return (await ref.get()).data();
}

async function main() {
  await clearEmulator();
  await db.doc(`users/${OWNER}`).set({ role: 'user', phone: OWNER });
  await db.doc('settings/app').set({ marketAutoApprove: false });

  await check('K0 sof: konstanta yoqiq, 3 til, kod', () => {
    assert.strictEqual(retired.MARKET_ADS_RETIRED, true);
    assert.strictEqual(retired.MARKET_AD_RETIRED, 'MARKET_AD_RETIRED');
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(retired.MARKET_AD_RETIRED_MESSAGES[l].includes('«＋»'), l);
  });

  await check('K1 muddati tugagan e\'lonni ega qayta joylashtirsa (inactive → pending) → inactive ga qaytadi, expiresAt o\'sha', async () => {
    const past = TS.fromMillis(Date.now() - 1000);
    await seed('k1', { status: 'inactive', autoExpiredAt: TS.fromMillis(Date.now() - 500), expiresAt: past });
    const d = await runUpdate('k1', { status: 'pending', updatedAt: TS.now() });
    assert.strictEqual(d.status, 'inactive');
    assert.ok(d.retiredRevertedAt, 'retiredRevertedAt');
    assert.strictEqual(d.expiresAt.toMillis(), past.toMillis());
  });

  await check('K2 AVTO rejim ham: inactive → pending → inactive (active bo\'lmaydi)', async () => {
    await db.doc('settings/app').set({ marketAutoApprove: true }, { merge: true });
    await seed('k2', { status: 'inactive' });
    const d = await runUpdate('k2', { status: 'pending' });
    assert.strictEqual(d.status, 'inactive');
    assert.strictEqual(d.publishedAt, undefined);
    await db.doc('settings/app').set({ marketAutoApprove: false }, { merge: true });
  });

  await check('K3 AVTO rejim: faol e\'lon tahriri (active → pending) → active, LEKIN expiresAt uzaymaydi', async () => {
    await db.doc('settings/app').set({ marketAutoApprove: true }, { merge: true });
    await seed('k3');
    const d = await runUpdate('k3', { status: 'pending', title: 'Velosiped 2' });
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.expiresAt.toMillis(), EXP.toMillis());
    await db.doc('settings/app').set({ marketAutoApprove: false }, { merge: true });
  });

  await check('K4 QO\'LDA: tahrir → pending (owner_edit), expiresAt uzaymaydi', async () => {
    await seed('k4');
    const d = await runUpdate('k4', { title: 'Yangi nom' });
    assert.strictEqual(d.status, 'pending');
    assert.strictEqual(d.moderationReason, 'owner_edit');
    assert.strictEqual(d.expiresAt.toMillis(), EXP.toMillis());
  });

  await check('K5 ega yashirishi (active → inactive) — avvalgidek, qaytarilmaydi', async () => {
    await seed('k5');
    const d = await runUpdate('k5', { status: 'inactive' });
    assert.strictEqual(d.status, 'inactive');
    assert.strictEqual(d.retiredRevertedAt, undefined);
  });

  await check('K6 admin yozuvi (moderatedAt o\'zgaradi) inactive → pending — tegilmaydi', async () => {
    await seed('k6', { status: 'inactive' });
    const d = await runUpdate('k6', { status: 'pending', moderatedAt: TS.fromMillis(5000) });
    assert.strictEqual(d.status, 'pending');
    assert.strictEqual(d.retiredRevertedAt, undefined);
  });

  await check('K7 ish e\'loni (type ≠ cheap_product) inactive → pending — tegilmaydi (regressiya)', async () => {
    await db.collection('ads').doc('k7').set({ type: 'ad', authorPhone: OWNER, status: 'inactive', title: 'Ish' });
    const d = await runUpdate('k7', { status: 'pending' });
    assert.strictEqual(d.status, 'pending');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
