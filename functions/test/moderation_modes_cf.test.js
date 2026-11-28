/**
 * Moderatsiya rejimlari (ega 2026-11-28, audit C-1) — HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   npm run test:moderation-modes-cf   (functions/ ichidan)
 *
 *   M1  adminSetModerationMode: maydon + UpdatedAt/By + admin_audit; bir xil qiymat — noop (audit yo'q)
 *   M2  realty: maydon yo'q = AVTO; AVTO bosilsa — noop; QO'LDA → false yoziladi
 *   M3  iste'fodagi (deviceBinding, restaurant) — MODE_RETIRED, hech narsa yozilmaydi
 *   M4  noma'lum rejim / enabled bool emas — diagnostik kod
 *   M5  rol: oddiy user — rad; dispatcher — panel rejimlari OK, producerVerify/supermarketPartner — rad
 *   M6  eski callable'lar (dating/market/jobs/producer/supermarketPartner) — o'sha maydon + audit kind moderation_mode_set
 *   M7  adminGetModerationModes — samarali qiymatlar
 *   M8  o'quvchilar: submitJobAd (jobs) va realty yaratish yagona qoida bilan ishlaydi (eski xatti-harakat)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-moderation-modes-cf';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const ADMIN = '998914100009';
const DISP = '998914100008';
const USER = '998914100001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function seed(settings) {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin', phone: ADMIN });
  await db.doc(`users/${DISP}`).set({ role: 'dispatcher', phone: DISP });
  await db.doc(`users/${USER}`).set({ role: 'user', phone: USER });
  if (settings) await db.doc('settings/app').set(settings);
}
const app = async () => (await db.doc('settings/app').get()).data() || {};
const audits = async () => (await db.collection('admin_audit').where('kind', '==', 'moderation_mode_set').get())
  .docs.map((d) => d.data());

async function main() {
  await seed({ otherField: 'keep' });
  await check('M1 maydon + UpdatedAt/By + audit; bir xil qiymat — noop', async () => {
    const r = await call('adminSetModerationMode', { mode: 'tv', enabled: true, reason: 'test' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.mode, r.enabled, r.changed], [true, 'tv', true, true]);
    const a = await app();
    assert.strictEqual(a.tvAutoApprove, true);
    assert.strictEqual(a.tvAutoApproveUpdatedBy, ADMIN);
    assert.ok(a.tvAutoApproveUpdatedAt);
    assert.strictEqual(a.otherField, 'keep');
    const r2 = await call('adminSetModerationMode', { mode: 'tv', enabled: true }, ADMIN);
    assert.strictEqual(r2.changed, false);
    const au = await audits();
    assert.strictEqual(au.length, 1);
    assert.deepStrictEqual([au[0].mode, au[0].field, au[0].from, au[0].to, au[0].actor, au[0].reason],
      ['tv', 'tvAutoApprove', false, true, ADMIN, 'test']);
  });

  await seed({});
  await check('M2 realty: yo\'q = AVTO → AVTO noop; QO\'LDA → false', async () => {
    assert.strictEqual((await call('adminSetModerationMode', { mode: 'realty', enabled: true }, ADMIN)).changed, false);
    assert.strictEqual((await app()).realtyAutoApprove, undefined);
    assert.strictEqual((await call('adminSetModerationMode', { mode: 'realty', enabled: false }, ADMIN)).changed, true);
    assert.strictEqual((await app()).realtyAutoApprove, false);
    const au = await audits();
    assert.deepStrictEqual([au.length, au[0].from, au[0].to], [1, true, false]);
  });

  await seed({ deviceBindingAutoApprove: false });
  await check('M3 iste\'fodagi rejim — MODE_RETIRED, yozuv yo\'q', async () => {
    await expectCode(call('adminSetModerationMode', { mode: 'deviceBinding', enabled: true }, ADMIN), 'MODE_RETIRED');
    await expectCode(call('adminSetModerationMode', { mode: 'restaurant', enabled: true }, ADMIN), 'MODE_RETIRED');
    const a = await app();
    assert.strictEqual(a.deviceBindingAutoApprove, false);
    assert.strictEqual(a.restaurantAutoApprove, undefined);
    assert.strictEqual((await audits()).length, 0);
  });

  await check('M4 noma\'lum rejim / enabled bool emas', async () => {
    await expectCode(call('adminSetModerationMode', { mode: 'nope', enabled: true }, ADMIN), 'MODE_UNKNOWN');
    await expectCode(call('adminSetModerationMode', { mode: '__proto__', enabled: true }, ADMIN), 'MODE_UNKNOWN');
    await expectCode(call('adminSetModerationMode', { mode: 'tv', enabled: 'true' }, ADMIN), 'MODE_ENABLED_INVALID');
    await expectCode(call('adminSetModerationMode', { mode: 'tv' }, ADMIN), 'MODE_ENABLED_INVALID');
  });

  await seed({});
  await check('M5 rol: user — rad; dispatcher — tv OK, producerVerify/supermarketPartner — rad', async () => {
    await expectCode(call('adminSetModerationMode', { mode: 'tv', enabled: true }, USER), 'PERMISSION_DENIED');
    await expectCode(fns.adminSetModerationMode.run({ mode: 'tv', enabled: true }, {}), 'UNAUTHENTICATED');
    assert.strictEqual((await call('adminSetModerationMode', { mode: 'tv', enabled: true }, DISP)).changed, true);
    await expectCode(call('adminSetModerationMode', { mode: 'producerVerify', enabled: true }, DISP), 'PERMISSION_DENIED');
    await expectCode(call('adminSetModerationMode', { mode: 'supermarketPartner', enabled: true }, DISP), 'PERMISSION_DENIED');
    const a = await app();
    assert.deepStrictEqual([a.tvAutoApprove, a.producerVerifyAutoApprove, a.supermarketPartnerAutoApprove],
      [true, undefined, undefined]);
  });

  await seed({});
  await check('M6 eski callable\'lar — o\'sha maydon + yagona audit', async () => {
    await call('adminSetDatingAutoApprove', { adminPhone: ADMIN, enabled: true }, ADMIN);
    await call('adminSetMarketAutoApprove', { adminPhone: ADMIN, enabled: true }, ADMIN);
    await call('adminSetJobsAutoApprove', { adminPhone: ADMIN, enabled: true }, ADMIN);
    await call('adminSetProducerAutoApprove', { enabled: true }, ADMIN);
    await call('adminSetSupermarketPartnerAutoApprove', { enabled: true }, ADMIN);
    const a = await app();
    assert.deepStrictEqual(
      [a.datingAutoApprove, a.marketAutoApprove, a.jobsAutoApprove, a.producerVerifyAutoApprove, a.supermarketPartnerAutoApprove],
      [true, true, true, true, true]);
    const au = await audits();
    assert.deepStrictEqual(au.map((x) => x.mode).sort(),
      ['dating', 'jobs', 'market', 'producerVerify', 'supermarketPartner']);
    assert.ok(au.every((x) => x.actor && x.source && x.source.startsWith('adminSet')));
    // Qayta — noop, audit ko'paymaydi.
    const r = await call('adminSetJobsAutoApprove', { adminPhone: ADMIN, enabled: true }, ADMIN);
    assert.deepStrictEqual([r.ok, r.enabled, r.changed], [true, true, false]);
    assert.strictEqual((await audits()).length, 5);
    // Eski: enabled yuborilmasa — false (avvalgidek `data.enabled === true`).
    await call('adminSetJobsAutoApprove', { adminPhone: ADMIN }, ADMIN);
    assert.strictEqual((await app()).jobsAutoApprove, false);
  });

  await seed({ tvAutoApprove: true, realtyAutoApprove: false });
  await check('M7 adminGetModerationModes — samarali qiymatlar; user — rad', async () => {
    const r = await call('adminGetModerationModes', {}, DISP);
    const by = Object.fromEntries(r.modes.map((m) => [m.mode, m]));
    assert.deepStrictEqual([by.tv.enabled, by.realty.enabled, by.jobs.enabled, by.realty.defaultOn],
      [true, false, false, true]);
    assert.strictEqual(by.deviceBinding, undefined);
    await expectCode(call('adminGetModerationModes', {}, USER), 'PERMISSION_DENIED');
  });

  await seed({});
  await check('M8 o\'quvchilar: realty yo\'q = AVTO; jobs/market/dating yo\'q = QO\'LDA (index.js yordamchilari)', async () => {
    const mm = require('../moderation_modes');
    assert.strictEqual(await mm.readModeAuto(db, 'realty'), true);
    assert.strictEqual(await mm.readModeAuto(db, 'jobs'), false);
    await db.doc('settings/app').set({ jobsAutoApprove: true, realtyAutoApprove: false }, { merge: true });
    assert.strictEqual(await mm.readModeAuto(db, 'realty'), false);
    assert.strictEqual(await mm.readModeAuto(db, 'jobs'), true);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
