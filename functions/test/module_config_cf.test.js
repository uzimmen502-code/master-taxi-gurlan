/**
 * «Ҳудудлар ва хизматлар» — `adminSaveModuleConfig` (functions/module_config.js),
 * ega 2026-10-08. Firestore — Emulator (tranzaksiya haqiqiy).
 *
 *   firebase emulators:exec --only firestore --project demo-module-config \
 *     "node functions/test/module_config_cf.test.js"
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-module-config';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const mc = require('../module_config');

const ADMIN = '998909990001';
const DISPATCHER = '998909990002';
const FINANCE = '998909990003';
const USER = '998901000001';

const api = {};
mc.attachModuleConfig(api, {
  functions, db, admin,
  callerPhone: (ctx) => String(ctx.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v || '').replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
});
const ctxOf = (p) => ({ auth: { uid: `u_${p}`, token: { phone_number: `+${p}` } } });
const save = (data, who = ADMIN) => api.adminSaveModuleConfig.run(data, ctxOf(who));
const codeOf = async (p) => { try { await p; return 'OK'; } catch (e) { return (e.details && e.details.code) || e.message; } };

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
const defaultsRef = db.collection('config').doc('module_defaults');
const gurlanRef = db.collection('geo_district_modules').doc('gurlan');
const areaRef = db.collection('service_area_modules').doc('svc_gurlan_markaz');

async function reset() {
  await Promise.all(['users', 'config', 'geo_district_modules', 'service_area_modules',
    'geo_districts', 'service_areas', 'admin_audit'].map(wipe));
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(FINANCE).set({ role: 'finance' });
  await db.collection('users').doc(USER).set({ role: 'user' });
  await db.collection('geo_districts').doc('gurlan').set({ regionId: 'xorazm', name: 'Гурлан' });
  await db.collection('service_areas').doc('svc_gurlan_markaz')
    .set({ districtId: 'gurlan', regionId: 'xorazm' });
  await defaultsRef.set({
    enforce: true,
    updatedBy: 'seed',
    modules: {
      local_taxi: { status: 'hidden' },
      marshrut: { status: 'hidden' },
      intercity: { status: 'enabled' },
      logistics: { status: 'soon' },
    },
  });
}
const auditCount = async () => (await db.collection('admin_audit').get()).size;

async function main() {
  // ── Sof funksiyalar ────────────────────────────────────────────────────
  await check('P1 normalizeStatus — Dart fromWire bilan bir xil', () => {
    assert.strictEqual(mc.normalizeStatus('enabled'), 'enabled');
    assert.strictEqual(mc.normalizeStatus('true'), 'enabled');
    assert.strictEqual(mc.normalizeStatus('comingSoon'), 'coming_soon');
    assert.strictEqual(mc.normalizeStatus('soon'), 'soon');
    assert.strictEqual(mc.normalizeStatus('disabled'), 'hidden');
    assert.strictEqual(mc.normalizeStatus('xyz'), 'hidden');
  });
  await check('P2 currentStatus — tuman: manualModules dan tashqari = meros (null)', () => {
    const d = { modules: { courier: { status: 'enabled' }, food: { status: 'hidden' } }, manualModules: ['courier'] };
    assert.strictEqual(mc.currentStatus(d, 'district', 'courier'), 'enabled');
    assert.strictEqual(mc.currentStatus(d, 'district', 'food'), null);
    assert.strictEqual(mc.currentStatus(d, 'global', 'food'), 'hidden');
    assert.strictEqual(mc.currentStatus(d, 'global', 'local_taxi'), null);
  });

  // ── Ruxsat ────────────────────────────────────────────────────────────
  await reset();
  const one = { scope: 'global', changes: [{ moduleId: 'local_taxi', from: 'hidden', to: 'enabled' }] };
  await check('A1 auth yo\'q → AUTH_REQUIRED', async () =>
    assert.strictEqual(await codeOf(api.adminSaveModuleConfig.run(one, {})), 'AUTH_REQUIRED'));
  await check('A2 oddiy user va finance → ADMIN_REQUIRED, hech narsa yozilmaydi', async () => {
    assert.strictEqual(await codeOf(save(one, USER)), 'ADMIN_REQUIRED');
    assert.strictEqual(await codeOf(save(one, FINANCE)), 'ADMIN_REQUIRED');
    assert.strictEqual((await defaultsRef.get()).data().modules.local_taxi.status, 'hidden');
    assert.strictEqual(await auditCount(), 0);
  });

  // ── Global: faqat o'zgargan katak + audit ─────────────────────────────
  await reset();
  await check('G1 faqat o\'zgargan modul yoziladi, qolganlari tegilmaydi', async () => {
    const r = await save(one);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.applied, 1);
    const d = (await defaultsRef.get()).data();
    assert.strictEqual(d.modules.local_taxi.status, 'enabled');
    assert.strictEqual(d.modules.marshrut.status, 'hidden');
    assert.strictEqual(d.modules.intercity.status, 'enabled');
    assert.strictEqual(d.modules.logistics.status, 'soon');
    assert.strictEqual(d.enforce, true);
    assert.strictEqual(d.updatedBy, ADMIN);
  });
  await check('G2 audit: kim, nima, qayerda — server vaqti bilan', async () => {
    const s = await db.collection('admin_audit').get();
    assert.strictEqual(s.size, 1);
    const a = s.docs[0].data();
    assert.strictEqual(a.kind, 'module_config_changed');
    assert.strictEqual(a.actor, ADMIN);
    assert.strictEqual(a.actorRole, 'admin');
    assert.strictEqual(a.scope, 'global');
    assert.strictEqual(a.targetId, 'module_defaults');
    assert.deepStrictEqual(a.changes, [{ moduleId: 'local_taxi', from: 'hidden', to: 'enabled' }]);
    assert.strictEqual(a.source, 'admin_ui');
    assert.ok(a.at && typeof a.at.toDate === 'function');
  });
  await check('G3 qayta yuborish (retry) — ikkinchi marta yozilmaydi, audit bitta', async () => {
    const r = await save(one);
    assert.strictEqual(r.applied, 0);
    assert.strictEqual(r.auditId, null);
    assert.strictEqual(await auditCount(), 1);
  });

  // ── Konflikt: eski sahifa boshqa adminning o'zgarishini qaytarmaydi ────
  await reset();
  await check('C1 serverda boshqa qiymat → MODULE_CONFIG_CONFLICT, hech narsa yozilmaydi', async () => {
    // Boshqa admin marshrutni «soon» qildi; eski sahifa «hidden → enabled» yuboradi.
    await defaultsRef.set({ modules: { marshrut: { status: 'soon' } } }, { merge: true });
    let details = null;
    try {
      await save({ scope: 'global', changes: [
        { moduleId: 'local_taxi', from: 'hidden', to: 'enabled' },
        { moduleId: 'marshrut', from: 'hidden', to: 'enabled' },
      ] });
    } catch (e) { details = e.details; }
    assert.ok(details, 'xato kutilgan edi');
    assert.strictEqual(details.code, 'MODULE_CONFIG_CONFLICT');
    assert.deepStrictEqual(details.conflicts, [{ moduleId: 'marshrut', expected: 'hidden', actual: 'soon' }]);
    const d = (await defaultsRef.get()).data();
    assert.strictEqual(d.modules.local_taxi.status, 'hidden', 'bir qismi ham yozilmasligi kerak');
    assert.strictEqual(d.modules.marshrut.status, 'soon');
    assert.strictEqual(await auditCount(), 0);
  });
  await check('C2 bir xil o\'zgarishni boshqa admin qilgan — konflikt emas, yozuv yo\'q', async () => {
    await defaultsRef.set({ modules: { local_taxi: { status: 'enabled' } } }, { merge: true });
    const r = await save(one);
    assert.strictEqual(r.applied, 0);
    assert.strictEqual(await auditCount(), 0);
  });

  // ── enforce ───────────────────────────────────────────────────────────
  await reset();
  await check('E1 enforce o\'zgarishi yoziladi va auditga tushadi', async () => {
    const r = await save({ scope: 'global', changes: [], enforce: { from: true, to: false } });
    assert.strictEqual(r.applied, 1);
    assert.strictEqual((await defaultsRef.get()).data().enforce, false);
    const a = (await db.collection('admin_audit').get()).docs[0].data();
    assert.deepStrictEqual(a.enforce, { from: true, to: false });
    assert.deepStrictEqual(a.changes, []);
  });

  // ── Tuman (region override) ───────────────────────────────────────────
  await reset();
  await check('D1 tumanda override qo\'yish: manualModules + geo serverdan', async () => {
    await save({ scope: 'district', targetId: 'gurlan', changes: [
      { moduleId: 'local_taxi', from: null, to: 'enabled' },
    ] });
    const d = (await gurlanRef.get()).data();
    assert.deepStrictEqual(d.manualModules, ['local_taxi']);
    assert.strictEqual(d.modules.local_taxi.status, 'enabled');
    assert.strictEqual(d.regionId, 'xorazm');
    assert.strictEqual(d.districtId, 'gurlan');
    assert.strictEqual(d.updatedBy, ADMIN);
  });
  await check('D2 «meros»ga qaytarish: manualModules va modul kaliti o\'chadi, boshqasi qoladi', async () => {
    await save({ scope: 'district', targetId: 'gurlan', changes: [
      { moduleId: 'courier', from: null, to: 'enabled' },
    ] });
    await save({ scope: 'district', targetId: 'gurlan', changes: [
      { moduleId: 'local_taxi', from: 'enabled', to: null },
    ] });
    const d = (await gurlanRef.get()).data();
    assert.deepStrictEqual(d.manualModules, ['courier']);
    assert.ok(!('local_taxi' in d.modules));
    assert.strictEqual(d.modules.courier.status, 'enabled');
    assert.strictEqual(await auditCount(), 3);
  });
  await check('D3 tumanda konflikt: boshqa admin o\'chirgan override', async () => {
    assert.strictEqual(await codeOf(save({ scope: 'district', targetId: 'gurlan', changes: [
      { moduleId: 'local_taxi', from: 'enabled', to: 'hidden' },
    ] })), 'MODULE_CONFIG_CONFLICT');
  });
  await check('D4 dispatcher ham saqlay oladi (rules isAdmin() bilan bir xil)', async () => {
    const r = await save({ scope: 'district', targetId: 'gurlan', changes: [
      { moduleId: 'food', from: null, to: 'hidden' },
    ] }, DISPATCHER);
    assert.strictEqual(r.applied, 1);
  });

  // ── MFY ───────────────────────────────────────────────────────────────
  await reset();
  await check('M1 MFY hujjati yo\'q — yaratiladi, geo maydonlar service_areas dan', async () => {
    await save({ scope: 'area', targetId: 'svc_gurlan_markaz', changes: [
      { moduleId: 'bread', from: null, to: 'enabled' },
    ] });
    const d = (await areaRef.get()).data();
    assert.strictEqual(d.serviceAreaId, 'svc_gurlan_markaz');
    assert.strictEqual(d.districtId, 'gurlan');
    assert.strictEqual(d.regionId, 'xorazm');
    assert.deepStrictEqual(d.manualModules, ['bread']);
  });

  // ── Kiruvchi ma'lumot tekshiruvi ──────────────────────────────────────
  await reset();
  const bad = async (data, code, name) => check(`V ${name} → ${code}`, async () =>
    assert.strictEqual(await codeOf(save(data)), code));
  await bad({ scope: 'planet', changes: one.changes }, 'SCOPE_INVALID', 'noma\'lum scope');
  await bad({ scope: 'global', changes: [] }, 'NO_CHANGES', 'bo\'sh so\'rov');
  await bad({ scope: 'global', changes: [{ moduleId: 'local_taxi', from: 'hidden', to: null }] },
    'STATUS_INVALID', 'globalda meros');
  await bad({ scope: 'global', changes: [{ moduleId: 'local_taxi', from: 'hidden', to: 'open' }] },
    'STATUS_INVALID', 'noma\'lum holat');
  await bad({ scope: 'global', changes: [{ moduleId: 'local_taxi', from: 'hidden', to: 'hidden' }] },
    'NO_CHANGE', 'from == to');
  await bad({ scope: 'global', changes: [
    { moduleId: 'local_taxi', from: 'hidden', to: 'enabled' },
    { moduleId: 'local_taxi', from: 'hidden', to: 'soon' },
  ] }, 'MODULE_INVALID', 'takror modul');
  await bad({ scope: 'global', changes: [{ moduleId: 'modules.x', from: null, to: 'hidden' }] },
    'MODULE_INVALID', 'nuqtali kalit');
  await bad({ scope: 'district', targetId: 'mars', changes: [{ moduleId: 'food', from: null, to: 'hidden' }] },
    'TARGET_NOT_FOUND', 'yo\'q tuman');
  await bad({ scope: 'district', targetId: 'a/b', changes: [{ moduleId: 'food', from: null, to: 'hidden' }] },
    'TARGET_INVALID', 'yo\'l belgisi');
  await bad({ scope: 'district', targetId: 'gurlan', changes: [], enforce: { from: true, to: false } },
    'ENFORCE_INVALID', 'tumanda enforce');
  await check('V hech bir xato so\'rov hech narsa yozmagan', async () =>
    assert.strictEqual(await auditCount(), 0));

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
