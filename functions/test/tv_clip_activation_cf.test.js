/**
 * `tv_clips.activatedAt` — сервер фаоллашув вақти (эга 2026-11-19), Firestore Emulator.
 * ҲАҚИҚИЙ `functions/index.js` (`onTvClipSocialPublish`) ва `tv_clip_activation.js`.
 *
 *   firebase emulators:exec --only firestore --project demo-tv-activation \
 *     "node test/tv_clip_activation_cf.test.js"
 *
 * Яратилди active → ёзилади (= createTime); pending → active → ёзилади (= updateTime);
 * retry → иккинчи марта ёзилмайди; эски ҳодиса кейинги фаоллашувни босмайди;
 * ҳозир active эмас → ёзилмайди; active → active (бошқа майдон) → тегилмайди.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-tv-activation';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { stampTvClipActivation } = require('../tv_clip_activation');

const db = admin.firestore();
const deps = { db, admin };
const col = db.collection('tv_clips');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const base = (extra = {}) => ({
  ownerPhone: '998912000001', title: 't', category: 'product', socialConsent: false,
  createdAt: admin.firestore.FieldValue.serverTimestamp(), ...extra,
});
const ms = (t) => (t && t.toMillis ? t.toMillis() : null);

async function main() {
  await check('A1 yaratildi active -> activatedAt = createTime', async () => {
    const ref = col.doc('a1');
    await ref.set(base({ status: 'active' }));
    const snap = await ref.get();
    assert.strictEqual(await stampTvClipActivation(deps, snap), 'written');
    const d = (await ref.get()).data();
    assert.strictEqual(ms(d.activatedAt), ms(snap.updateTime));
  });

  await check('A2 retry (o\'sha hodisa) -> yozilmaydi, qiymat o\'zgarmaydi', async () => {
    const ref = col.doc('a1');
    const before = (await ref.get()).data().activatedAt;
    // Hodisa snapshoti — birinchi yozuvdagi updateTime bilan (stamp yozuvi undan keyin).
    const fake = { id: 'a1', ref, updateTime: before };
    assert.strictEqual(await stampTvClipActivation(deps, fake), 'skip');
    assert.strictEqual(ms((await ref.get()).data().activatedAt), ms(before));
  });

  await check('A3 pending -> active (moderatsiya) -> activatedAt = tasdiq vaqti', async () => {
    const ref = col.doc('a3');
    await ref.set(base({ status: 'pending', category: 'service' }));
    await new Promise((r) => setTimeout(r, 30));
    await ref.update({ status: 'active' });
    const snap = await ref.get();
    assert.strictEqual(await stampTvClipActivation(deps, snap), 'written');
    const d = (await ref.get()).data();
    assert.strictEqual(ms(d.activatedAt), ms(snap.updateTime));
    assert.ok(ms(d.activatedAt) > ms(d.createdAt), 'tasdiq yaratilishdan keyin');
  });

  await check('A4 eski hodisa keyingi faollashuvni bosmaydi', async () => {
    const ref = col.doc('a3');
    const cur = (await ref.get()).data().activatedAt;
    const old = { id: 'a3', ref, updateTime: admin.firestore.Timestamp.fromMillis(ms(cur) - 60000) };
    assert.strictEqual(await stampTvClipActivation(deps, old), 'skip');
    assert.strictEqual(ms((await ref.get()).data().activatedAt), ms(cur));
  });

  await check('A5 hozir active emas (blocked) -> yozilmaydi', async () => {
    const ref = col.doc('a5');
    await ref.set(base({ status: 'active' }));
    const snap = await ref.get();
    await ref.update({ status: 'blocked' });
    assert.strictEqual(await stampTvClipActivation(deps, snap), 'skip');
    assert.strictEqual((await ref.get()).data().activatedAt, undefined);
  });

  await check('A6 hujjat yo\'q -> skip, xato yo\'q', async () => {
    const ref = col.doc('a6-missing');
    const fake = { id: 'a6-missing', ref, updateTime: admin.firestore.Timestamp.now() };
    assert.strictEqual(await stampTvClipActivation(deps, fake), 'skip');
  });

  // Trigger orqali (haqiqiy index.js eksporti): ijtimoiy joylash rozilik yo'q — joylamaydi.
  const trig = (before, after, id) => fns.onTvClipSocialPublish.run(
      { before, after }, { params: { clipId: id }, eventId: `e-${id}-${Date.now()}` });

  await check('T1 trigger: yaratildi active -> activatedAt yoziladi', async () => {
    const ref = col.doc('t1');
    await ref.set(base({ status: 'active', category: 'product' }));
    const after = await ref.get();
    const before = await col.doc('t1-none').get(); // exists=false
    await trig(before, after, 't1');
    const d = (await ref.get()).data();
    assert.strictEqual(ms(d.activatedAt), ms(after.updateTime));
  });

  await check('T2 trigger: active -> active (tahrir) -> activatedAt tegilmaydi', async () => {
    const ref = col.doc('t1');
    const before = await ref.get();
    const was = before.data().activatedAt;
    await ref.update({ title: 'yangi' });
    const after = await ref.get();
    await trig(before, after, 't1');
    assert.strictEqual(ms((await ref.get()).data().activatedAt), ms(was));
  });

  await check('T3 trigger: pending yaratildi -> yozilmaydi', async () => {
    const ref = col.doc('t3');
    await ref.set(base({ status: 'pending' }));
    const after = await ref.get();
    const before = await col.doc('t3-none').get();
    await trig(before, after, 't3');
    assert.strictEqual((await ref.get()).data().activatedAt, undefined);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
