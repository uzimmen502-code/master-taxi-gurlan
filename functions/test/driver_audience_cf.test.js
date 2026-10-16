/**
 * Ҳайдовчи аудиторияси — ҲУҚУҚДАН (capability), `users.role` дан эмас
 * (эга, 2026-10-16: «ҳайдовчи роли» тушунчасидан кетиш, 1-босқич).
 * HAQIQIY Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-driver-audience \
 *     "node functions/test/driver_audience_cf.test.js"
 *
 *   A  янги оқим ҳайдовчиси (role: user + capability) «ҳайдовчи» аудиториясида
 *   B  эски белги (role: driver) ЭНДИ ҳисобга олинмайди — фақат ҳуқуқ (union ўчирилган, 2026-10-17)
 *   C  «фойдаланувчи» аудиториясида ҳайдовчи ЙЎҚ (эски қоида: ҳайдовчи — user эмас)
 *   D  ишламайдиган ҳолат (suspended / not_registered) ёки турсиз — ҳайдовчи эмас
 *   E  tokenсиз / қисқа token ўтказиб юборилади; такрорий token бир марта
 *   F  «all» ҳаммага; «courier» ўзгармаган
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-driver-audience';

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const aud = require('../driver_audience');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

async function wipe() {
  for (const col of ['users', 'provider_capabilities']) {
    const s = await db.collection(col).get();
    await Promise.all(s.docs.map((d) => d.ref.delete()));
  }
}

async function person(phone, { role = 'user', token, status, types, noPrimary = false } = {}) {
  const acc = `acc_${phone}`;
  await db.collection('users').doc(phone).set({
    phone, role, accountId: acc, ...(token ? { fcmToken: token } : {}),
  });
  if (status) {
    await db.collection('provider_capabilities').doc(acc).set({
      identity: noPrimary ? { accountId: acc } : { accountId: acc, primaryUid: phone },
      status: { taxi: status },
      taxi: { active: true, taxiTypes: types || [] },
    });
  }
}
const tok = (s) => `token_${s}_xxxxxxxxxx`;
const sorted = (a) => [...a].sort();

(async () => {
  await check('A янги оқим ҳайдовчиси «driver» аудиториясида (role: user бўлса ҳам)', async () => {
    await wipe();
    await person('998901110001', { token: tok('new'), status: 'starter', types: ['local'] });
    await person('998901110002', { token: tok('plain') });
    assert.deepStrictEqual(await aud.collectFcmTokensForAudience(db, 'driver'), [tok('new')]);
  });

  await check('A2 verified ва verification_required ҳам ҳайдовчи', async () => {
    await wipe();
    await person('998901110003', { token: tok('v'), status: 'verified', types: ['intercity'] });
    await person('998901110004', { token: tok('vr'), status: 'verification_required', types: ['marshrut'] });
    assert.deepStrictEqual(sorted(await aud.collectFcmTokensForAudience(db, 'driver')), sorted([tok('v'), tok('vr')]));
  });

  await check('B эски role: driver ҳуқуқсиз — «driver» аудиториясида ЙЎҚ; ҳуқуқли бўлса бор (такрор йўқ)', async () => {
    await wipe();
    await person('998901110005', { role: 'driver', token: tok('old') });
    await person('998901110006', { role: 'driver', token: tok('both'), status: 'starter', types: ['local'] });
    const t = await aud.collectFcmTokensForAudience(db, 'driver');
    assert.deepStrictEqual(t, [tok('both')]);
  });

  await check('C «user» аудиториясида capability ҳайдовчи ЙЎҚ, оддий фойдаланувчи бор', async () => {
    await wipe();
    await person('998901110007', { token: tok('drv'), status: 'starter', types: ['local'] });
    await person('998901110008', { token: tok('plain') });
    await person('998901110009', { role: 'driver', token: tok('olddrv') });
    assert.deepStrictEqual(await aud.collectFcmTokensForAudience(db, 'user'), [tok('plain')]);
  });

  await check('D suspended / not_registered / турсиз — ҳайдовчи эмас', async () => {
    await wipe();
    await person('998901110010', { token: tok('susp'), status: 'suspended', types: ['local'] });
    await person('998901110011', { token: tok('notreg'), status: 'not_registered', types: ['local'] });
    await person('998901110012', { token: tok('notypes'), status: 'starter', types: [] });
    assert.deepStrictEqual(await aud.collectFcmTokensForAudience(db, 'driver'), []);
    // улар «user» аудиториясида қолади (ҳайдовчи эмас)
    assert.deepStrictEqual(
      sorted(await aud.collectFcmTokensForAudience(db, 'user')),
      sorted([tok('susp'), tok('notreg'), tok('notypes')]),
    );
  });

  await check('D2 primaryUid йўқ capability — ўтказиб юборилади (хато эмас)', async () => {
    await wipe();
    await person('998901110013', { token: tok('x'), status: 'starter', types: ['local'], noPrimary: true });
    assert.deepStrictEqual(await aud.collectFcmTokensForAudience(db, 'driver'), []);
  });

  await check('E tokensiz ва қисқа token ўтказилади', async () => {
    await wipe();
    await person('998901110014', { status: 'starter', types: ['local'] });
    await person('998901110015', { token: 'short', status: 'starter', types: ['local'] });
    await person('998901110016', { token: tok('ok'), status: 'starter', types: ['local'] });
    assert.deepStrictEqual(await aud.collectFcmTokensForAudience(db, 'driver'), [tok('ok')]);
  });

  await check('F all — ҳамма, courier — фақат role: courier', async () => {
    await wipe();
    await person('998901110017', { token: tok('a'), status: 'starter', types: ['local'] });
    await person('998901110018', { token: tok('b') });
    await person('998901110019', { role: 'courier', token: tok('c') });
    assert.deepStrictEqual(
      sorted(await aud.collectFcmTokensForAudience(db, 'all')), sorted([tok('a'), tok('b'), tok('c')]));
    assert.deepStrictEqual(await aud.collectFcmTokensForAudience(db, 'courier'), [tok('c')]);
  });

  await check('G taxiDriverUids: 9 хонали primaryUid каноннга келади', async () => {
    await wipe();
    await db.collection('provider_capabilities').doc('acc_g').set({
      identity: { primaryUid: '901110020' }, status: { taxi: 'starter' }, taxi: { taxiTypes: ['local'] },
    });
    assert.deepStrictEqual([...(await aud.taxiDriverUids(db))], ['998901110020']);
  });

  await check('H саҳифалаш: pageSize дан кўп ҳайдовчи ҳам тўлиқ йиғилади', async () => {
    await wipe();
    for (let i = 0; i < 7; i++) {
      await person(`99890222${String(1000 + i)}`, { token: tok(`p${i}`), status: 'starter', types: ['local'] });
    }
    const set = await aud.taxiDriverUids(db, { pageSize: 3 });
    assert.strictEqual(set.size, 7);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
