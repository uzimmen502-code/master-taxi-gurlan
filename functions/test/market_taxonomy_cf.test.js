/**
 * «Бозорлар» — `adminSetMarketTaxonomy` callable, ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-market-taxonomy \
 *     "node test/market_taxonomy_cf.test.js"
 *
 * Admin v0→v1 (ҳужжат + taxonomy_history/v1 + admin_audit), оддий фойдаланувчи рад, версия конфликти,
 * нотўғри мазмун → TAXONOMY_INVALID (details.errors), қайта юбориш версияни оширмайди.
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-market-taxonomy';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const ADMIN = '998915000001';
const SUPER = '998915000002';
const DISPATCHER = '998915000003';
const USER = '998912000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (data, who) => fns.adminSetMarketTaxonomy.run(data, who ? ctxOf(who) : {});
const V1 = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'tools', 'data', 'market_taxonomy_v1.json'), 'utf8'));
const clone = () => JSON.parse(JSON.stringify(V1));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code, status) {
  let caught;
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    if (status) assert.strictEqual(e.code, status, `status ${e.code}`);
    caught = e;
    return true;
  });
  return caught;
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const taxDoc = async () => (await db.collection('taxonomy').doc('markets').get());
const audits = async () => (await db.collection('admin_audit').where('kind', '==', 'market_taxonomy_set').get()).docs.map((d) => d.data());

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(USER).set({ role: 'user' });

  await check('C1 оддий фойдаланувчи / dispatcher / токенсиз — рад, ҳеч нарса ёзилмайди', async () => {
    await assert.rejects(call({ taxonomy: V1, expectedVersion: 0 }, USER), (e) => e.code === 'permission-denied');
    await assert.rejects(call({ taxonomy: V1, expectedVersion: 0 }, DISPATCHER), (e) => e.code === 'permission-denied');
    await assert.rejects(call({ taxonomy: V1, expectedVersion: 0 }, null), (e) => e.code === 'unauthenticated');
    assert.strictEqual((await taxDoc()).exists, false);
    assert.strictEqual((await audits()).length, 0);
  });

  await check('C2 нотўғри мазмун → invalid-argument TAXONOMY_INVALID, details.errors (stack йўқ); ёзилмайди', async () => {
    const bad = clone(); delete bad.markets.meat.names.ru; bad.markets.farm.priceUnits = ['ton'];
    const e = await expectCode(call({ taxonomy: bad, expectedVersion: 0 }, ADMIN), 'TAXONOMY_INVALID', 'invalid-argument');
    assert.ok(e.details.errors.includes('NAME_MISSING markets.meat.names.ru'), JSON.stringify(e.details.errors));
    assert.ok(e.details.errors.includes('PRICE_UNIT_INVALID markets.farm.priceUnits[0]'));
    assert.ok(!JSON.stringify(e.details).includes('at '), 'details ичида stack бўлмасин');
    await expectCode(call({ taxonomy: null, expectedVersion: 0 }, ADMIN), 'TAXONOMY_INVALID');
    assert.strictEqual((await taxDoc()).exists, false);
  });

  await check('C3 expectedVersion йўқ / манфий / каср → EXPECTED_VERSION_INVALID', async () => {
    await expectCode(call({ taxonomy: V1 }, ADMIN), 'EXPECTED_VERSION_INVALID', 'invalid-argument');
    await expectCode(call({ taxonomy: V1, expectedVersion: -1 }, ADMIN), 'EXPECTED_VERSION_INVALID');
    await expectCode(call({ taxonomy: V1, expectedVersion: 0.5 }, ADMIN), 'EXPECTED_VERSION_INVALID');
  });

  await check('C4 admin v0→v1: ҳужжат + taxonomy_history/v1 + admin_audit', async () => {
    const r = await call({ taxonomy: V1, expectedVersion: 0 }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, version: 1, changed: true });
    const d = (await taxDoc()).data();
    assert.strictEqual(d.version, 1);
    assert.strictEqual(d.updatedBy, ADMIN);
    assert.ok(d.updatedAt && typeof d.updatedAt.toMillis === 'function');
    assert.deepStrictEqual(Object.keys(d.markets).sort(), ['auto', 'farm', 'livestock', 'meat']);
    assert.deepStrictEqual(d.markets.meat.priceUnits, ['kg']);
    const h = (await db.collection('taxonomy_history').doc('v1').get()).data();
    assert.strictEqual(h.version, 1);
    assert.strictEqual(h.previousVersion, null);
    assert.deepStrictEqual(h.markets, d.markets);
    const a = await audits();
    assert.strictEqual(a.length, 1);
    assert.deepStrictEqual([a[0].actor, a[0].target, a[0].version], [ADMIN, 'v1', 1]);
  });

  await check('C5 қайта юбориш (expectedVersion 0, шу мазмун) — версия ОШМАЙДИ, аудит қўшилмайди', async () => {
    const r = await call({ taxonomy: V1, expectedVersion: 0 }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, version: 1, changed: false });
    const r2 = await call({ taxonomy: V1, expectedVersion: 1 }, ADMIN);
    assert.deepStrictEqual(r2, { ok: true, version: 1, changed: false });
    assert.strictEqual((await audits()).length, 1);
  });

  await check('C6 эски версия билан бошқа мазмун → failed-precondition TAXONOMY_VERSION_CONFLICT, ёзилмайди', async () => {
    const changed = clone(); changed.markets.meat.imageUrl = 'https://cdn.example/meat.jpg';
    const e = await expectCode(call({ taxonomy: changed, expectedVersion: 0 }, ADMIN), 'TAXONOMY_VERSION_CONFLICT', 'failed-precondition');
    assert.strictEqual(e.details.currentVersion, 1);
    await expectCode(call({ taxonomy: changed, expectedVersion: 5 }, ADMIN), 'TAXONOMY_VERSION_CONFLICT');
    assert.strictEqual((await taxDoc()).data().markets.meat.imageUrl, '');
  });

  await check('C7 superadmin v1→v2: сатрлар trim, тарих previousVersion 1, аудит 2 та', async () => {
    const changed = clone(); changed.markets.meat.imageUrl = '  https://cdn.example/meat.jpg  ';
    const r = await call({ taxonomy: changed, expectedVersion: 1 }, SUPER);
    assert.deepStrictEqual(r, { ok: true, version: 2, changed: true });
    const d = (await taxDoc()).data();
    assert.strictEqual(d.markets.meat.imageUrl, 'https://cdn.example/meat.jpg');
    assert.strictEqual(d.updatedBy, SUPER);
    const h = (await db.collection('taxonomy_history').doc('v2').get()).data();
    assert.strictEqual(h.previousVersion, 1);
    assert.ok((await db.collection('taxonomy_history').doc('v1').get()).exists, 'v1 тарихи сақланади');
    assert.strictEqual((await audits()).length, 2);
  });

  await check('C8 параллел икки admin бир expectedVersion билан — фақат биттаси ғолиб', async () => {
    const a = clone(); a.markets.farm.imageUrl = 'https://cdn.example/a.jpg';
    const b = clone(); b.markets.farm.imageUrl = 'https://cdn.example/b.jpg';
    const out = await Promise.allSettled([call({ taxonomy: a, expectedVersion: 2 }, ADMIN), call({ taxonomy: b, expectedVersion: 2 }, SUPER)]);
    const ok = out.filter((o) => o.status === 'fulfilled');
    const bad = out.filter((o) => o.status === 'rejected');
    assert.strictEqual(ok.length, 1, JSON.stringify(out.map((o) => o.status)));
    assert.strictEqual(bad[0].reason.details.code, 'TAXONOMY_VERSION_CONFLICT');
    assert.strictEqual((await taxDoc()).data().version, 3);
    assert.strictEqual((await audits()).length, 3);
  });

  const ok = results.filter(Boolean).length;
  console.log(`\n${ok} passed, ${results.length - ok} failed`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
