/**
 * «Кўчмас мулк» — эълон яратиш ва пакет харидлари: ҲАҚИҚИЙ функциялар,
 * Firestore Emulator (2026-10-18 тузатишлари).
 *
 *   npm run test:realty-submit-cf   (functions/ ичидан)
 *
 * Қулфланади:
 *   S1  эълон яратилади; расм — фақат ўзининг `ads/{телефон}/…` манзили
 *   S2  ИДЕМПОТЕНТ: бир хил калит иккинчи эълон яратмайди ва ЎРИН емайди
 *   S3  калит фойдаланувчига боғланган: бошқа фойдаланувчи ўз эълонини яратади
 *   S4  ПОЙГА: битта ўрин қолганда икки параллел юборишдан фақат биттаси ўтади
 *   S5  расм: бегона сайт / бошқа эганинг папкаси / бегона bucket — рад
 *   S6  таҳрир: эълондаги эски расм сақланади, янги бегона расм — рад
 *   S7  эганинг БИРИНЧИ икки параллел чақируви битта калит билан тугайди
 *   P1  пакет: бир хил калит икки марта ЕЧМАЙДИ
 *   P2  пакет: бир хил калит бошқа ўлчам билан — idem_conflict; бошқа фойдаланувчи — алоҳида
 *   P3  калит яроқсиз — idem_required
 *   P4  профессионал пакет: такрорий чақирув икки марта ечмайди
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-realty-submit';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const crypto = require('crypto');
const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

const A = '998901110001';
const B = '998901110002';
const BUCKET = `${process.env.GCLOUD_PROJECT}.firebasestorage.app`;

const ctx = (phone) => ({ auth: { uid: phone, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctx(phone));
const key = () => crypto.randomUUID();
const img = (phone, n = 'a') =>
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(`ads/${phone}/${n}.jpg`)}?alt=media&token=t`;

const payload = (extra = {}) => ({
  deal: 'sale', title: 'Уч хонали уй', text: 'Тавсиф матни', lat: 41.844, lng: 60.392,
  addressText: 'Гурлан, Навоий кўчаси 12', contactMode: 'owner', tier: 'plain',
  imageUrls: [], idempotencyKey: key(), ...extra,
});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function rejects(promise, reason) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.message, reason, `kutilgan sabab ${reason}, keldi ${e.message}`);
    return;
  }
  assert.fail(`${reason} bilan rad etilishi kerak edi`);
}

async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => db.recursiveDelete(d.ref)));
}
async function reset() {
  await Promise.all(['users', 'realty_listings', 'wallet_idempotency', 'settings'].map(wipe));
  await db.doc(`users/${A}`).set({ name: 'Али', bonusBalance: 500000 });
  await db.doc(`users/${B}`).set({ name: 'Вали', bonusBalance: 500000 });
}
const listingsOf = async (phone) => {
  const u = (await db.doc(`users/${phone}`).get()).data() || {};
  if (!u.realtyOwnerKey) return [];
  return (await db.collection('realty_listings').where('ownerKey', '==', u.realtyOwnerKey).get()).docs;
};
const balance = async (phone) => ((await db.doc(`users/${phone}`).get()).data() || {}).bonusBalance;
const unlocks = async (phone) => ((await db.doc(`users/${phone}`).get()).data() || {}).realtyUnlocksLeft || 0;

(async () => {
  await reset();
  await check('S1 эълон яратилади, ўз расми билан; ёпиқ ҳужжат ҳам ёзилади', async () => {
    const r = await call('submitRealtyListing', payload({ imageUrls: [img(A)] }), A);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.freeLeft, 1);
    const pub = (await db.doc(`realty_listings/${r.listingId}`).get()).data();
    assert.deepStrictEqual(pub.imageUrls, [img(A)]);
    const det = (await db.doc(`realty_listings/${r.listingId}/private/detail`).get()).data();
    assert.strictEqual(det.ownerId, A);
  });

  await reset();
  await check('S2 бир хил калит: иккинчи эълон ЯРАТИЛМАЙДИ, ўрин емайди', async () => {
    const p = payload();
    const r1 = await call('submitRealtyListing', p, A);
    const r2 = await call('submitRealtyListing', p, A);
    assert.strictEqual(r2.listingId, r1.listingId);
    assert.strictEqual((await listingsOf(A)).length, 1);
    // Ўрин 1 та банд: яна биттаси ўтади, учинчиси — лимит.
    await call('submitRealtyListing', payload(), A);
    await rejects(call('submitRealtyListing', payload(), A), 'free_limit_reached');
    assert.strictEqual((await listingsOf(A)).length, 2);
  });

  await reset();
  await check('S3 калит фойдаланувчига боғланган: B ўз эълонини яратади, A нинг натижасини олмайди', async () => {
    const p = payload();
    const ra = await call('submitRealtyListing', p, A);
    const rb = await call('submitRealtyListing', p, B);
    assert.notStrictEqual(rb.listingId, ra.listingId);
    assert.strictEqual((await listingsOf(A)).length, 1);
    assert.strictEqual((await listingsOf(B)).length, 1);
  });

  await reset();
  await check('S4 ПОЙГА: битта ўрин қолганда икки параллел юборишдан фақат биттаси ўтади', async () => {
    await call('submitRealtyListing', payload(), A); // 1/2 банд
    const out = await Promise.allSettled([
      call('submitRealtyListing', payload(), A),
      call('submitRealtyListing', payload(), A),
    ]);
    const ok = out.filter((o) => o.status === 'fulfilled');
    const bad = out.filter((o) => o.status === 'rejected');
    assert.strictEqual(ok.length, 1, `ўтган: ${ok.length}`);
    assert.strictEqual(bad[0].reason.message, 'free_limit_reached');
    assert.strictEqual((await listingsOf(A)).length, 2);
  });

  await reset();
  await check('S5 расм: бегона сайт, бошқа эганинг папкаси, бегона bucket — рад; ҳеч нарса яратилмайди', async () => {
    await rejects(call('submitRealtyListing', payload({ imageUrls: ['https://evil.example/x.jpg'] }), A), 'image_invalid');
    await rejects(call('submitRealtyListing', payload({ imageUrls: [img(B)] }), A), 'image_invalid');
    const foreign = `https://firebasestorage.googleapis.com/v0/b/attacker/o/${encodeURIComponent(`ads/${A}/a.jpg`)}?alt=media`;
    await rejects(call('submitRealtyListing', payload({ imageUrls: [foreign] }), A), 'image_invalid');
    assert.strictEqual((await listingsOf(A)).length, 0);
  });

  await reset();
  await check('S6 таҳрир: эски расм сақланади, янги бегона расм рад этилади', async () => {
    const r = await call('submitRealtyListing', payload(), A);
    const legacy = 'https://old.example/legacy.jpg';
    await db.doc(`realty_listings/${r.listingId}`).update({ imageUrls: [legacy] });
    const edit = (urls) => call('updateRealtyListing', { ...payload({ imageUrls: urls }), listingId: r.listingId }, A);
    await edit([legacy, img(A, 'new')]);
    const cur = (await db.doc(`realty_listings/${r.listingId}`).get()).data();
    assert.deepStrictEqual(cur.imageUrls, [legacy, img(A, 'new')]);
    await rejects(edit([legacy, 'https://evil.example/new.jpg']), 'image_invalid');
  });

  await reset();
  await check('S7 эганинг БИРИНЧИ икки параллел чақируви: битта калит, иккови ҳам ўтади', async () => {
    await db.doc(`users/${A}`).set({ name: 'Али' }); // realtyOwnerKey йўқ
    const out = await Promise.all([
      call('submitRealtyListing', payload(), A),
      call('submitRealtyListing', payload(), A),
    ]);
    assert.notStrictEqual(out[0].listingId, out[1].listingId);
    const keys = new Set();
    for (const r of out) keys.add((await db.doc(`realty_listings/${r.listingId}`).get()).data().ownerKey);
    assert.strictEqual(keys.size, 1, `калитлар: ${[...keys].join(',')}`);
    assert.strictEqual((await listingsOf(A)).length, 2);
  });

  await reset();
  await check('P1 пакет: бир хил калит икки марта ЕЧМАЙДИ', async () => {
    const k = key();
    const r1 = await call('purchaseRealtyPackage', { idempotencyKey: k, size: 5 }, A);
    const b1 = await balance(A);
    const r2 = await call('purchaseRealtyPackage', { idempotencyKey: k, size: 5 }, A);
    assert.strictEqual(r1.unlocksLeft, 5);
    assert.strictEqual(r2.unlocksLeft, 5);
    assert.strictEqual(await balance(A), b1, 'иккинчи чақирув ҳамённи яна ечмаслиги керак');
    assert.strictEqual(await unlocks(A), 5);
    assert.strictEqual(b1, 500000 - 30000);
  });

  await reset();
  await check('P2 бир хил калит бошқа ўлчам билан — idem_conflict; бошқа фойдаланувчи — алоҳида', async () => {
    const k = key();
    await call('purchaseRealtyPackage', { idempotencyKey: k, size: 5 }, A);
    await rejects(call('purchaseRealtyPackage', { idempotencyKey: k, size: 10 }, A), 'idem_conflict');
    assert.strictEqual(await unlocks(A), 5);
    const rb = await call('purchaseRealtyPackage', { idempotencyKey: k, size: 5 }, B);
    assert.strictEqual(rb.unlocksLeft, 5);
    assert.strictEqual(await balance(B), 500000 - 30000);
  });

  await reset();
  await check('P3 калит яроқсиз/йўқ — idem_required, пул ечилмайди', async () => {
    await rejects(call('purchaseRealtyPackage', { size: 5 }, A), 'idem_required');
    await rejects(call('purchaseRealtyPackage', { idempotencyKey: '../x', size: 5 }, A), 'idem_required');
    await rejects(call('purchaseRealtyPackage', { idempotencyKey: 'a'.repeat(65), size: 5 }, A), 'idem_required');
    assert.strictEqual(await balance(A), 500000);
  });

  await reset();
  await check('P4 профессионал пакет: такрорий чақирув икки марта ечмайди', async () => {
    const k = key();
    await call('purchaseRealtyProPackage', { idempotencyKey: k, planId: 'pro_25' }, A);
    const b1 = await balance(A);
    await call('purchaseRealtyProPackage', { idempotencyKey: k, planId: 'pro_25' }, A);
    assert.strictEqual(await balance(A), b1);
    assert.strictEqual(b1, 500000 - 250000);
    await rejects(call('purchaseRealtyProPackage', { idempotencyKey: k, planId: 'pro_60' }, A), 'idem_conflict');
  });

  await reset();
  await check('L1 бепул лимит админ созламасидан (realtyFreeLimit=3): 3 та ўтади, 4-си рад; квота 3 дейди', async () => {
    await db.doc('settings/app').set({ realtyFreeLimit: 3 });
    for (let i = 0; i < 3; i += 1) await call('submitRealtyListing', payload(), A);
    await rejects(call('submitRealtyListing', payload(), A), 'free_limit_reached');
    const q = await call('getRealtyQuota', {}, A);
    assert.strictEqual(q.limit, 3);
    assert.strictEqual(q.used, 3);
  });

  await reset();
  await check('L2 созлама йўқ — бошланғич 2 (орқага мослик)', async () => {
    await call('submitRealtyListing', payload(), A);
    await call('submitRealtyListing', payload(), A);
    await rejects(call('submitRealtyListing', payload(), A), 'free_limit_reached');
    assert.strictEqual((await call('getRealtyQuota', {}, A)).limit, 2);
  });

  await reset();
  await check('L3 лимит кўпайтирилса — аввал тўлган фойдаланувчи яна қўша олади', async () => {
    await call('submitRealtyListing', payload(), A);
    await call('submitRealtyListing', payload(), A);
    await rejects(call('submitRealtyListing', payload(), A), 'free_limit_reached');
    await db.doc('settings/app').set({ realtyFreeLimit: 4 });
    await call('submitRealtyListing', payload(), A);
    assert.strictEqual((await listingsOf(A)).length, 3);
  });

  await reset();
  await check('K1 пакет ўлчамлари админ созламасидан: нарх рўйхатида фақат шулар; бошқа ўлчам рад', async () => {
    await db.doc('settings/app').set({ realtyPackagePricing: { '3': 10000, '20': 40000 } });
    const pr = await call('getRealtyPackagePricing', {}, A);
    assert.deepStrictEqual(pr.pricing, { '3': 10000, '20': 40000 });
    const r = await call('purchaseRealtyPackage', { idempotencyKey: key(), size: 20 }, A);
    assert.strictEqual(r.unlocksLeft, 20);
    assert.strictEqual(await balance(A), 500000 - 40000);
    await rejects(call('purchaseRealtyPackage', { idempotencyKey: key(), size: 5 }, A), 'bad_package_size');
  });

  await reset();
  await check('K2 созлама йўқ — [5, 10] бошланғич нархлар билан', async () => {
    const pr = await call('getRealtyPackagePricing', {}, A);
    assert.deepStrictEqual(pr.pricing, { '5': 30000, '10': 50000 });
  });

  // ─── Админ: объект сонларини созлаш (`adminSetRealtyCounts`) ───
  const ADMIN = '998909990001';
  const DISPATCHER = '998909990002';
  const countsInput = (extra = {}) => ({
    adminPhone: ADMIN,
    freeLimit: 4,
    packages: [{ size: 3, price: 9000 }, { size: 20, price: 40000 }],
    proPlans: [{ id: 'pro_10', objects: 10, days: 30, price: 100000 }],
    ...extra,
  });
  const auditsOf = async () =>
    (await db.collection('admin_audit').where('kind', '==', 'realty_counts_changed').get()).docs.map((x) => x.data());
  async function resetAdmin() {
    await reset();
    await wipe('admin_audit');
    await db.doc(`users/${ADMIN}`).set({ role: 'admin', name: 'Admin' });
    await db.doc(`users/${DISPATCHER}`).set({ role: 'dispatcher', name: 'Disp' });
  }

  await resetAdmin();
  await check('C1 админ сақлайди: созламалар ёзилади, аудит ёзилади, энди ШУ лимит ишлайди', async () => {
    await db.doc('settings/app').set({ realtyPackagePricing: { '5': 30000, '10': 50000 }, realtyAgentPhone: '998900000000' });
    const r = await call('adminSetRealtyCounts', countsInput(), ADMIN);
    assert.strictEqual(r.ok, true);
    const app = (await db.doc('settings/app').get()).data();
    assert.strictEqual(app.realtyFreeLimit, 4);
    assert.deepStrictEqual(app.realtyPackagePricing, { '3': 9000, '20': 40000 }, 'эски ўлчамлар (5, 10) тозаланади');
    assert.deepStrictEqual(app.realtyProPlans, [{ id: 'pro_10', objects: 10, days: 30, price: 100000 }]);
    assert.strictEqual(app.realtyAgentPhone, '998900000000', 'бошқа созламаларга тегилмайди');
    const audits = await auditsOf();
    assert.strictEqual(audits.length, 1);
    assert.strictEqual(audits[0].actor, ADMIN);
    assert.strictEqual(audits[0].after.freeLimit, 4);
    assert.deepStrictEqual(audits[0].before.packagePricing, { '5': 30000, '10': 50000 });
    assert.strictEqual((await call('getRealtyQuota', {}, A)).limit, 4);
    const pr = await call('getRealtyPackagePricing', {}, A);
    assert.deepStrictEqual(pr.pricing, { '3': 9000, '20': 40000 });
    const pp = await call('getRealtyProPlans', {}, A);
    assert.deepStrictEqual(pp.plans, [{ id: 'pro_10', objects: 10, days: 30, price: 100000 }]);
  });

  await resetAdmin();
  await check('C2 бўш бепул лимит — созлама ўчирилади, бошланғич (2) қайтади', async () => {
    await call('adminSetRealtyCounts', countsInput({ freeLimit: 6 }), ADMIN);
    assert.strictEqual((await call('getRealtyQuota', {}, A)).limit, 6);
    await call('adminSetRealtyCounts', countsInput({ freeLimit: '' }), ADMIN);
    const app = (await db.doc('settings/app').get()).data();
    assert.ok(!('realtyFreeLimit' in app));
    assert.strictEqual((await call('getRealtyQuota', {}, A)).limit, 2);
  });

  await resetAdmin();
  await check('C3 оддий фойдаланувчи ва диспетчер сақлай олмайди; ҳеч нарса ёзилмайди', async () => {
    await rejects(call('adminSetRealtyCounts', countsInput({ adminPhone: A }), A), 'Admin only');
    await rejects(call('adminSetRealtyCounts', countsInput({ adminPhone: DISPATCHER }), DISPATCHER), 'admin_only');
    assert.strictEqual((await auditsOf()).length, 0);
    assert.ok(!(await db.doc('settings/app').get()).exists || !('realtyFreeLimit' in (await db.doc('settings/app').get()).data()));
  });

  await resetAdmin();
  await check('C4 яроқсиз қиймат — сабаби билан рад, созлама ва аудит ўзгармайди', async () => {
    await rejects(call('adminSetRealtyCounts', countsInput({ freeLimit: 0 }), ADMIN), 'free_limit_invalid');
    await rejects(call('adminSetRealtyCounts', countsInput({ packages: [{ size: 5, price: 30000 }, { size: 10, price: 90000 }] }), ADMIN), 'package_per_object');
    await rejects(call('adminSetRealtyCounts', countsInput({ proPlans: [{ id: 'x', objects: 999, days: 30, price: 1 }] }), ADMIN), 'plan_invalid');
    assert.strictEqual((await auditsOf()).length, 0);
    assert.strictEqual((await call('getRealtyQuota', {}, A)).limit, 2);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
