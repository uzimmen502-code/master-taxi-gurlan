/**
 * `functions/tools/enable_business_map.js` — Firestore Emulator.
 *   firebase emulators:exec --only firestore --project demo-enable-bm "node test/enable_business_map_tool.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-enable-bm';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { enableBusinessMap } = require('../tools/enable_business_map');
const { currentStatus } = require('../module_config');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const dm = async (id) => (await db.collection('geo_district_modules').doc(id).get()).data();
const audits = async () => (await db.collection('admin_audit').where('kind', '==', 'module_config_changed').get()).docs.map((d) => d.data());

async function main() {
  await clearEmulator();
  await db.collection('geo_districts').doc('gurlan').set({ regionId: 'xorazm' });
  await db.collection('geo_districts').doc('urganch_shahri').set({ regionId: 'xorazm' });
  // Prodagiga o'xshash: mavjud qo'lda sozlangan modullar
  await db.collection('geo_district_modules').doc('gurlan').set({
    districtId: 'gurlan', regionId: 'xorazm',
    modules: { bread: { status: 'hidden' }, courier: { status: 'enabled' } }, manualModules: ['bread', 'courier'],
  });

  await check('T1 dry-run: hech narsa yozilmaydi, reja would_set', async () => {
    const r = await enableBusinessMap(db, admin, { apply: false });
    assert.deepStrictEqual(r.map((x) => x.action), ['would_set', 'would_set']);
    assert.strictEqual(currentStatus(await dm('gurlan'), 'district', 'business_map'), null);
    assert.strictEqual((await audits()).length, 0);
  });

  await check('T2 apply: faqat business_map yoqiladi; boshqa modullar va manualModules saqlanadi; audit yoziladi', async () => {
    const r = await enableBusinessMap(db, admin, { apply: true });
    assert.deepStrictEqual(r.map((x) => x.action), ['set', 'set']);
    const g = await dm('gurlan');
    assert.strictEqual(currentStatus(g, 'district', 'business_map'), 'enabled');
    assert.strictEqual(currentStatus(g, 'district', 'bread'), 'hidden', 'bread tegilmadi');
    assert.strictEqual(currentStatus(g, 'district', 'courier'), 'enabled');
    assert.deepStrictEqual(g.manualModules, ['bread', 'business_map', 'courier']);
    const u = await dm('urganch_shahri');
    assert.strictEqual(u.districtId, 'urganch_shahri');
    assert.strictEqual(u.regionId, 'xorazm');
    assert.strictEqual(currentStatus(u, 'district', 'business_map'), 'enabled');
    const a = await audits();
    assert.strictEqual(a.length, 2);
    assert.deepStrictEqual(a.find((x) => x.targetId === 'gurlan').changes, [{ moduleId: 'business_map', from: null, to: 'enabled' }]);
    assert.strictEqual(a[0].scope, 'district');
  });

  await check('T3 takror apply — already, audit ortmaydi (idempotent)', async () => {
    const r = await enableBusinessMap(db, admin, { apply: true });
    assert.deepStrictEqual(r.map((x) => x.action), ['already', 'already']);
    assert.strictEqual((await audits()).length, 2);
  });

  await check('T4 yo\'q tuman — o\'tkazib yuboriladi; noto\'g\'ri status — xato; orqaga qaytarish --status=hidden', async () => {
    const r = await enableBusinessMap(db, admin, { districts: ['yoq_tuman'], apply: true });
    assert.strictEqual(r[0].action, 'skip_no_such_district');
    await assert.rejects(enableBusinessMap(db, admin, { status: 'on', apply: true }));
    const back = await enableBusinessMap(db, admin, { districts: ['gurlan'], status: 'hidden', apply: true });
    assert.strictEqual(back[0].from, 'enabled');
    assert.strictEqual(currentStatus(await dm('gurlan'), 'district', 'business_map'), 'hidden');
  });

  await check('G1 --global: baseline katagi yoqiladi; boshqa modullar va enforce tegilmaydi; audit scope global; takror — already', async () => {
    const { enableBusinessMapGlobal } = require('../tools/enable_business_map');
    await db.collection('config').doc('module_defaults').set({ enforce: true, modules: { restaurants: { status: 'enabled' }, bread: { status: 'hidden' } } });
    const dry = await enableBusinessMapGlobal(db, admin, { apply: false });
    assert.deepStrictEqual([dry.action, dry.from], ['would_set', null]);
    assert.strictEqual(currentStatus((await db.collection('config').doc('module_defaults').get()).data(), 'global', 'business_map'), null, 'dry-run yozmaydi');
    const r = await enableBusinessMapGlobal(db, admin, { apply: true });
    assert.deepStrictEqual([r.action, r.to], ['set', 'enabled']);
    const d = (await db.collection('config').doc('module_defaults').get()).data();
    assert.strictEqual(currentStatus(d, 'global', 'business_map'), 'enabled');
    assert.strictEqual(currentStatus(d, 'global', 'restaurants'), 'enabled');
    assert.strictEqual(currentStatus(d, 'global', 'bread'), 'hidden');
    assert.strictEqual(d.enforce, true, 'enforce tegilmadi');
    const g = (await audits()).filter((x) => x.scope === 'global');
    assert.strictEqual(g.length, 1);
    assert.strictEqual(g[0].targetId, 'module_defaults');
    assert.deepStrictEqual(g[0].changes, [{ moduleId: 'business_map', from: null, to: 'enabled' }]);
    assert.strictEqual((await enableBusinessMapGlobal(db, admin, { apply: true })).action, 'already');
    assert.strictEqual((await audits()).filter((x) => x.scope === 'global').length, 1);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
