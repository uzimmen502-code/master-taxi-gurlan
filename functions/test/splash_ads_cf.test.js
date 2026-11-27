/**
 * «Splash реклама» — callable'лар (ҲАҚИҚИЙ index.js), Firestore Emulator (эга 2026-11-28).
 *
 *   firebase emulators:exec --only firestore --project demo-splash-ads "node test/splash_ads_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-splash-ads';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const s = require('../splash_ads');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const anonCtx = (uid) => ({ auth: { uid, token: {} } });
const call = (name, data, who) => fns[name].run(data, typeof who === 'string' ? ctxOf(who) : (who || {}));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => { assert.strictEqual((e.details && e.details.code) || e.message, code); return true; });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get()).data();
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());

const NOW = Date.now();
const IMG = 'https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/platform_images%2Fsplash_ads%2Fa.jpg?alt=media';
const AD = {
  id: 'cola_dec', title: 'Cola', text: { uz_Cyrl: 'Кола', uz_Latn: 'Kola', ru: 'Кола' }, imageUrl: IMG, linkUrl: '',
  startAtMs: NOW - 3600000, endAtMs: NOW + 7 * 86400000, districts: ['urganch', 'gurlan', 'gurlan'], priority: 5, active: true,
};

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${USER}`).set({ role: 'user' });

  await check('V1 validateAd: positive / negative / boundary', async () => {
    const ok = s.validateAd(AD);
    assert.ok(ok.ok);
    assert.deepStrictEqual(ok.clean.districts, ['gurlan', 'urganch']); // такрор олиб ташланди, тартибланди
    assert.ok(s.validateAd({ ...AD, imageUrl: '', text: { uz_Cyrl: 'Фақат матн' } }).ok);
    assert.deepStrictEqual(s.validateAd({ ...AD, imageUrl: '', text: {} }).errors, ['content']);
    assert.deepStrictEqual(s.validateAd({ ...AD, imageUrl: 'https://evil.example/a.jpg' }).errors, ['imageUrl']);
    assert.deepStrictEqual(s.validateAd({ ...AD, linkUrl: 'http://x.uz' }).errors, ['linkUrl']);
    assert.deepStrictEqual(s.validateAd({ ...AD, endAtMs: AD.startAtMs }).errors, ['window']);
    assert.deepStrictEqual(s.validateAd({ ...AD, endAtMs: AD.startAtMs + 367 * 86400000 }).errors, ['window']);
    assert.ok(s.validateAd({ ...AD, endAtMs: AD.startAtMs + 366 * 86400000 }).ok);
    assert.deepStrictEqual(s.validateAd({ ...AD, districts: ['Gurlan'] }).errors, ['districts']);
    assert.deepStrictEqual(s.validateAd({ ...AD, priority: 101 }).errors, ['priority']);
    assert.ok(s.validateAd({ ...AD, priority: 100 }).ok);
    assert.deepStrictEqual(s.validateAd({ ...AD, active: 'yes' }).errors, ['active']);
    assert.deepStrictEqual(s.validateAd({ ...AD, title: 'x'.repeat(81) }).errors, ['title']);
  });

  await check('C1 adminUpsertSplashAd: рухсат, текширув, visible, аудит, идемпотент, PII йўқ', async () => {
    await expectCode(call('adminUpsertSplashAd', { ad: AD }, USER), 'PERMISSION_DENIED');
    await expectCode(call('adminUpsertSplashAd', { ad: AD }), 'UNAUTHENTICATED');
    await expectCode(call('adminUpsertSplashAd', { ad: { ...AD, priority: -1 } }, ADMIN), 'SPLASH_AD_INVALID');
    await expectCode(call('adminUpsertSplashAd', { ad: { ...AD, id: 'bad id!' } }, ADMIN), 'SPLASH_AD_INVALID');
    const r = await call('adminUpsertSplashAd', { ad: AD, reason: 'шартнома 12' }, ADMIN);
    assert.deepStrictEqual([r.adId, r.changed, r.version], ['cola_dec', true, 1]);
    const d = await get('splash_ads/cola_dec');
    assert.strictEqual(d.visible, true);
    assert.strictEqual(d.startAt.toMillis(), AD.startAtMs);
    assert.deepStrictEqual(d.districts, ['gurlan', 'urganch']);
    assert.ok(!('updatedBy' in d) && !JSON.stringify(d).includes(ADMIN), 'оммавий ҳужжатда админ телефони йўқ');
    assert.strictEqual((await call('adminUpsertSplashAd', { ad: AD }, ADMIN)).changed, false);
    const off = await call('adminUpsertSplashAd', { ad: { ...AD, active: false } }, ADMIN);
    assert.deepStrictEqual([off.changed, off.version], [true, 2]);
    assert.strictEqual((await get('splash_ads/cola_dec')).visible, false);
    const a = await audits('splash_ad_set');
    assert.strictEqual(a.length, 2);
    assert.ok(a.every((x) => x.actor === ADMIN));
    assert.ok(a.some((x) => x.before === null && x.reason === 'шартнома 12'));
    const auto = await call('adminUpsertSplashAd', { ad: { ...AD, id: undefined, title: 'Auto' } }, ADMIN);
    assert.ok(/^[A-Za-z0-9]{20}$/.test(auto.adId));
  });

  await check('C2 adminDeleteSplashAd: рухсат, аудит (аввалги ҳолат), идемпотент', async () => {
    await expectCode(call('adminDeleteSplashAd', { id: 'cola_dec' }, USER), 'PERMISSION_DENIED');
    const r = await call('adminDeleteSplashAd', { id: 'cola_dec', reason: 'муддат тугади' }, ADMIN);
    assert.strictEqual(r.deleted, true);
    assert.strictEqual(await get('splash_ads/cola_dec'), undefined);
    const a = await audits('splash_ad_delete');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].before.title, 'Cola');
    assert.strictEqual((await call('adminDeleteSplashAd', { id: 'cola_dec' }, ADMIN)).deleted, false);
    assert.strictEqual((await audits('splash_ad_delete')).length, 1);
  });

  await check('S1 sanitizeImpressions: кунига ≤3, 7 кун ойнаси, келажак/нотўғри кун рад', async () => {
    const today = s.dayKeyOf(NOW);
    const yest = s.dayKeyOf(NOW - 86400000);
    const old = s.dayKeyOf(NOW - 9 * 86400000);
    const fut = s.dayKeyOf(NOW + 86400000);
    const out = s.sanitizeImpressions({ [yest]: { a1: 2, a2: 5 }, [today]: { a1: 1 }, [old]: { a1: 1 }, [fut]: { a1: 1 }, bad: { a1: 1 } }, NOW);
    assert.deepStrictEqual(out, [{ day: yest, ads: { a1: 2, a2: 1 }, total: 3 }, { day: today, ads: { a1: 1 }, total: 1 }]);
    assert.strictEqual(s.sanitizeImpressions('x', NOW), null);
    assert.deepStrictEqual(s.sanitizeImpressions({ [yest]: { 'bad id': 2, a1: 0, a2: 1.5 } }, NOW), []);
  });

  await check('C3 recordSplashImpressions: йиғма, фақат мавжуд реклама, идемпотент (retry), аноним ҳам', async () => {
    await call('adminUpsertSplashAd', { ad: { ...AD, id: 'ad_one' } }, ADMIN);
    const yest = s.dayKeyOf(NOW - 86400000);
    await expectCode(call('recordSplashImpressions', { days: {} }), 'UNAUTHENTICATED');
    await expectCode(call('recordSplashImpressions', { days: 5 }, USER), 'INVALID_REQUEST');
    const r = await call('recordSplashImpressions', { days: { [yest]: { ad_one: 3, ghost_ad: 2 } } }, USER);
    assert.strictEqual(r.recorded, 3);
    assert.deepStrictEqual(
      (({ impressions, devices }) => ({ impressions, devices }))(await get(`splash_ad_stats/ad_one_${yest}`)),
      { impressions: 3, devices: 1 },
    );
    assert.strictEqual(await get(`splash_ad_stats/ghost_ad_${yest}`), undefined);
    assert.strictEqual((await call('recordSplashImpressions', { days: { [yest]: { ad_one: 3 } } }, USER)).recorded, 0);
    const log = await get(`splash_ad_imp_log/${USER}_${yest}`);
    assert.ok(log && log.expireAt && log.n === 3);
    assert.strictEqual((await call('recordSplashImpressions', { days: { [yest]: { ad_one: 1 } } }, anonCtx('anonX'))).recorded, 1);
    const st = await get(`splash_ad_stats/ad_one_${yest}`);
    assert.deepStrictEqual([st.impressions, st.devices], [4, 2]);
    assert.ok(await get(`splash_ad_imp_log/a_anonX_${yest}`));
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
