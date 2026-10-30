/**
 * requestCapability — admin «Ҳудудлар ва хизматлар» `courier` модул дарвозаси (аудит 2026-10-31,
 * MEDIUM-4). HAQIQIY Firestore (Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-caps-gate \
 *     "node functions_demand/test/capabilities_module_gate_emulator.test.js"
 *
 * Qulflanadi:
 *   K1 courier enabled → applied (yangi ariza)
 *   K2 courier soon/hidden → MODULE_CLOSED (details.code), hech narsa yozilmaydi
 *   K3 taksi arizasi courier yopiq bo'lsa ham ishlaydi (faqat kuryer darvozasi)
 *   K4 courier yopiq, lekin ariza allaqachon `applied` / ishlayapti → o'zgarishsiz javob (xato emas)
 *   K5 global hidden + tuman override enabled → shu tumandagi foydalanuvchi o'tadi
 *   K6 config/module_defaults yo'q → fail-open (eski xatti-harakat)
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-caps-gate';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const caps = require('../core/capabilities');
const gate = require('../core/module_gate');
const { makeRequestCapability } = require('../api/capabilities');

const A = '998901110001'; // gurlan
const B = '998901110002'; // xiva
const NOW = new Date('2026-10-31T10:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const req = makeRequestCapability({ db, now: () => NOW });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function reset(courier) {
  await clearEmulator();
  gate.resetCache();
  await db.doc(`users/${A}`).set({ phone: A, districtId: 'gurlan' });
  await db.doc(`users/${B}`).set({ phone: B, districtId: 'xiva' });
  if (courier) {
    await db.doc('config/module_defaults').set({ enforce: true, modules: { courier: { status: courier } } });
  }
}
async function rejectsClosed(promise) {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(e.code, 'failed-precondition');
    assert.strictEqual(e.details && e.details.code, 'MODULE_CLOSED');
    assert.strictEqual(e.details.moduleId, 'courier');
    return true;
  });
}
const capCount = async () => (await db.collection('provider_capabilities').get()).size;

(async () => {
  await check('K1 courier enabled → applied', async () => {
    await reset('enabled');
    const r = await req({ service: 'courier' }, ctx(A));
    assert.strictEqual(r.status, caps.COURIER.applied);
  });
  await check('K2 courier soon / hidden / coming_soon → MODULE_CLOSED, hech narsa yozilmaydi', async () => {
    for (const st of ['soon', 'hidden', 'coming_soon']) {
      await reset(st);
      await rejectsClosed(req({ service: 'courier' }, ctx(A)));
      assert.strictEqual(await capCount(), 0);
      assert.strictEqual(((await db.doc(`users/${A}`).get()).data() || {}).accountId, undefined, 'accountId yozilmadi');
    }
  });
  await check('K3 taksi arizasi courier yopiq bo\'lsa ham o\'tadi', async () => {
    await reset('hidden');
    const r = await req({ service: 'taxi' }, ctx(A));
    assert.strictEqual(r.status, caps.TAXI.starter);
  });
  await check('K4 yopiq modulda mavjud ariza (applied) va ishlayotgan kuryer — o\'zgarishsiz javob', async () => {
    await reset('enabled');
    const r1 = await req({ service: 'courier' }, ctx(A));
    await db.doc('config/module_defaults').set({ enforce: true, modules: { courier: { status: 'hidden' } } });
    gate.resetCache();
    const r2 = await req({ service: 'courier' }, ctx(A));
    assert.strictEqual(r2.changed, false);
    assert.strictEqual(r2.status, caps.COURIER.applied);
    await db.doc(`provider_capabilities/${r1.accountId}`).set({ status: { courier: caps.COURIER.approved } }, { merge: true });
    const r3 = await req({ service: 'courier' }, ctx(A));
    assert.strictEqual(r3.changed, false);
    assert.strictEqual(r3.status, caps.COURIER.approved);
  });
  await check('K5 global hidden + gurlan override enabled → A o\'tadi, B yopiq', async () => {
    await reset('hidden');
    await db.doc('geo_district_modules/gurlan').set({ modules: { courier: { status: 'enabled' } }, manualModules: ['courier'] });
    gate.resetCache();
    assert.strictEqual((await req({ service: 'courier' }, ctx(A))).status, caps.COURIER.applied);
    await rejectsClosed(req({ service: 'courier' }, ctx(B)));
  });
  await check('K6 config/module_defaults yo\'q → fail-open (eski xatti-harakat)', async () => {
    await reset(null);
    assert.strictEqual((await req({ service: 'courier' }, ctx(A))).status, caps.COURIER.applied);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
