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
    assert.strictEqual(ok.clean.weight, 1); // сукут
    assert.strictEqual(s.validateAd({ ...AD, weight: 100000000 }).clean.weight, 100000000);
    assert.deepStrictEqual(s.validateAd({ ...AD, weight: 0 }).errors, ['weight']);
    assert.deepStrictEqual(s.validateAd({ ...AD, weight: 1.5 }).errors, ['weight']);
    assert.deepStrictEqual(s.validateAd({ ...AD, regionIds: ['xorazm', 'xorazm'] }).clean.regionIds, ['xorazm']);
    assert.deepStrictEqual(s.validateAd({ ...AD, regionIds: ['Xorazm'] }).errors, ['regionIds']);
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
    assert.deepStrictEqual([d.areaKeys, d.weight, d.source], [['d:gurlan', 'd:urganch'], 1, 'admin']);
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

  const IMG_L = (l) => `https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/platform_images%2Fsplash_ads%2Fhouse_${l}.png?alt=media`;
  const HOUSE = {
    id: 'ava_house_republic', title: 'AVA намуна', text: { uz_Cyrl: 'Бу ерда сизнинг рекламангиз бўлиши мумкин' },
    imageUrl: IMG_L('uz_Cyrl'), imageUrls: { ru: IMG_L('ru'), uz_Cyrl: IMG_L('uz_Cyrl'), uz_Latn: IMG_L('uz_Latn') },
    linkUrl: '', startAtMs: NOW - 3600000, endAtMs: NOW + 365 * 86400000, priority: 0, weight: 1, active: true, house: true,
  };

  await check('V2 validateAd: намуна (house) ва тил расмлари — positive / negative / boundary', async () => {
    const ok = s.validateAd(HOUSE);
    assert.ok(ok.ok, JSON.stringify(ok.errors));
    assert.strictEqual(ok.clean.house, true);
    assert.deepStrictEqual(Object.keys(ok.clean.imageUrls), ['uz_Cyrl', 'uz_Latn', 'ru']); // LANGS тартиби
    assert.strictEqual(s.validateAd(AD).clean.house, undefined); // юборилмаган — upsert мавжудини сақлайди
    assert.strictEqual(s.validateAd(AD).clean.imageUrls, undefined);
    assert.deepStrictEqual(s.validateAd({ ...HOUSE, house: 'yes' }).errors, ['house']);
    assert.deepStrictEqual(s.validateAd({ ...HOUSE, imageUrls: { en: IMG_L('en') } }).errors, ['imageUrls']);
    assert.deepStrictEqual(s.validateAd({ ...HOUSE, imageUrls: { ru: 'https://evil.example/a.png' } }).errors, ['imageUrls']);
    assert.deepStrictEqual(s.validateAd({ ...HOUSE, imageUrls: ['x'] }).errors, ['imageUrls']);
    assert.deepStrictEqual(s.validateAd({ ...HOUSE, imageUrl: '' }).errors, ['imageUrl']); // эски мижоз учун сукут расм шарт
    assert.deepStrictEqual(s.validateAd({ ...HOUSE, imageUrls: { ru: '' } }).clean.imageUrls, {}); // бўш — эътиборсиз
    const f = s.adminAdFields(ok.clean, admin.firestore.Timestamp);
    assert.deepStrictEqual([f.house, f.source, f.areaKeys, f.visible], [true, 'admin', ['all'], true]);
  });

  await check('C1b adminUpsertSplashAd: намуна сақланади; эски форма (house/imageUrls юбормайди) уларни йўқотмайди', async () => {
    const r = await call('adminUpsertSplashAd', { ad: HOUSE }, ADMIN);
    assert.deepStrictEqual([r.changed, r.version], [true, 1]);
    let d = await get('splash_ads/ava_house_republic');
    assert.deepStrictEqual([d.house, d.source, d.weight, d.areaKeys], [true, 'admin', 1, ['all']]);
    assert.strictEqual(d.imageUrls.uz_Latn, IMG_L('uz_Latn'));
    // Эски админ формаси: house/imageUrls йўқ, расм ўша — ўзгариш йўқ (идемпотент).
    const legacy = { ...HOUSE };
    delete legacy.house;
    delete legacy.imageUrls;
    assert.strictEqual((await call('adminUpsertSplashAd', { ad: legacy }, ADMIN)).changed, false);
    // Эски форма матнни ўзгартирди — house ва тил расмлари сақланади.
    await call('adminUpsertSplashAd', { ad: { ...legacy, text: { uz_Cyrl: 'Янги матн' } } }, ADMIN);
    d = await get('splash_ads/ava_house_republic');
    assert.deepStrictEqual([d.house, Object.keys(d.imageUrls).length, d.version], [true, 3, 2]);
    // Админ асосий расмни алмаштирди — эски тил расмлари олиб ташланади (янги расм ҳамма тилда).
    await call('adminUpsertSplashAd', { ad: { ...legacy, text: { uz_Cyrl: 'Янги матн' }, imageUrl: IMG } }, ADMIN);
    d = await get('splash_ads/ava_house_republic');
    assert.deepStrictEqual([d.house, d.imageUrls, d.imageUrl], [true, {}, IMG]);
    // Аниқ house:false — оддий админ рекламага айланади.
    await call('adminUpsertSplashAd', { ad: { ...legacy, text: { uz_Cyrl: 'Янги матн' }, imageUrl: IMG, house: false } }, ADMIN);
    assert.strictEqual((await get('splash_ads/ava_house_republic')).house, false);
    const a = (await audits('splash_ad_set')).filter((x) => /ava_house_republic/.test(x.target));
    assert.strictEqual(a.length, 4);
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

  await check('S1 sanitizeImpressions: ҳар очилиш (3/кун йўқ), ҳисобот чегараси 200, 7 кун ойнаси, келажак/нотўғри кун рад', async () => {
    const today = s.dayKeyOf(NOW);
    const yest = s.dayKeyOf(NOW - 86400000);
    const old = s.dayKeyOf(NOW - 9 * 86400000);
    const fut = s.dayKeyOf(NOW + 86400000);
    const out = s.sanitizeImpressions({ [yest]: { a1: 2, a2: 5 }, [today]: { a1: 1 }, [old]: { a1: 1 }, [fut]: { a1: 1 }, bad: { a1: 1 } }, NOW);
    assert.deepStrictEqual(out, [{ day: yest, ads: { a1: 2, a2: 5 }, total: 7 }, { day: today, ads: { a1: 1 }, total: 1 }]);
    assert.strictEqual(s.MAX_IMPRESSIONS_PER_DAY, 200);
    assert.deepStrictEqual(s.sanitizeImpressions({ [yest]: { a1: 150, a2: 100 } }, NOW), [{ day: yest, ads: { a1: 150, a2: 50 }, total: 200 }]);
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

  // ══════════ ПУЛЛИК РЕКЛАМА ══════════
  const ADV = '998913000001';
  const ADV2 = '998913000002';
  const today = s.dayKeyOf(NOW);
  const advImg = (p) => `https://firebasestorage.googleapis.com/v0/b/x.appspot.com/o/ads%2F${p}%2F1.jpg?alt=media&token=t`;
  const REQ = (over = {}) => ({
    clientRequestId: 'req_00000001', days: 3, startDay: today, areaLevel: 'district', districts: ['gurlan', 'urganch'],
    creative: { imageUrl: advImg(ADV), text: 'Гурлан нон', linkUrl: 'https://ava.uz' }, ...over,
  });
  const bal = async (p) => (await get(`users/${p}`)).bonusBalance;
  await db.doc(`users/${ADV}`).set({ role: 'user', districtId: 'gurlan', appLang: 'uz_Latn', bonusBalance: 500000 });
  await db.doc(`users/${ADV2}`).set({ role: 'user', districtId: 'gurlan', appLang: 'ru', bonusBalance: 1000 });
  await db.doc('geo_districts/gurlan').set({ regionId: 'xorazm', active: true });
  await db.doc('geo_districts/urganch').set({ regionId: 'xorazm', active: true });
  await db.doc('geo_districts/oldone').set({ regionId: 'xorazm', active: false });
  await db.doc('geo_regions/xorazm').set({ name: 'Xorazm', active: true });

  await check('P1 соф: нарх (даража × туманлар × кун), чегаралар, сана, ҳудуд калити, расм эгаси', async () => {
    const perDay = { district: 20000, region: 60000, republic: 150000 };
    assert.deepStrictEqual(s.priceOf(perDay, 'district', 1, 1), { pricePerDay: 20000, amount: 20000 });
    assert.deepStrictEqual(s.priceOf(perDay, 'district', 3, 5), { pricePerDay: 60000, amount: 300000 });
    assert.deepStrictEqual(s.priceOf(perDay, 'region', 3, 7), { pricePerDay: 60000, amount: 420000 }); // туманлар сони аҳамиятсиз
    assert.deepStrictEqual(s.priceOf(perDay, 'republic', 1, 3), { pricePerDay: 150000, amount: 450000 });
    for (const d of [0, 2, 4, 6, 8, 3.5]) assert.strictEqual(s.priceOf(perDay, 'district', 1, d), null, `days ${d}`);
    assert.strictEqual(s.priceOf(perDay, 'district', 11, 1), null);
    assert.strictEqual(s.priceOf(perDay, 'district', 10, 1).pricePerDay, 200000);
    assert.strictEqual(s.priceOf({ district: 1.5 }, 'district', 1, 1), null);
    assert.ok(Number.isSafeInteger(s.priceOf(perDay, 'republic', 1, 7).amount));
    assert.deepStrictEqual(s.areaKeysOf([], []), ['all']);
    assert.deepStrictEqual(s.areaKeysOf(['gurlan'], ['xorazm']), ['d:gurlan', 'r:xorazm']);
    assert.strictEqual(s.dayStartMs('2026-11-28'), Date.UTC(2026, 10, 27, 19));
    assert.strictEqual(s.dayStartMs('2026-02-30'), null);
    assert.ok(s.imageOwnedBy(advImg(ADV), ADV));
    assert.ok(s.imageOwnedBy(advImg(ADV.slice(3)), ADV));
    assert.ok(!s.imageOwnedBy(advImg(ADV2), ADV));
    assert.ok(!s.imageOwnedBy('https://evil.example/o/ads%2F998913000001%2Fa.jpg', ADV));
    const v = s.validatePurchase(REQ(), ADV, NOW);
    assert.ok(v.ok, JSON.stringify(v.errors));
    assert.strictEqual(v.clean.endAtMs - v.clean.startAtMs, 3 * 86400000);
    assert.deepStrictEqual(v.clean.creative.text, { uz_Cyrl: 'Гурлан нон', uz_Latn: 'Гурлан нон', ru: 'Гурлан нон' });
    const yest = s.dayKeyOf(NOW - 86400000);
    const far = s.dayKeyOf(NOW + 61 * 86400000);
    assert.deepStrictEqual(s.validatePurchase(REQ({ startDay: yest }), ADV, NOW).errors, ['startDay']);
    assert.deepStrictEqual(s.validatePurchase(REQ({ startDay: far }), ADV, NOW).errors, ['startDay']);
    assert.ok(s.validatePurchase(REQ({ startDay: s.dayKeyOf(NOW + 60 * 86400000) }), ADV, NOW).ok);
    assert.deepStrictEqual(s.validatePurchase(REQ({ days: 2 }), ADV, NOW).errors, ['days']);
    assert.deepStrictEqual(s.validatePurchase(REQ({ districts: [] }), ADV, NOW).errors, ['districts']);
    assert.deepStrictEqual(s.validatePurchase(REQ({ areaLevel: 'region', regionId: 'Bad!' }), ADV, NOW).errors, ['regionId']);
    assert.ok(s.validatePurchase(REQ({ areaLevel: 'republic', districts: undefined }), ADV, NOW).ok);
    assert.deepStrictEqual(s.validatePurchase(REQ({ creative: { imageUrl: advImg(ADV2) } }), ADV, NOW).errors, ['imageUrl']);
    assert.deepStrictEqual(s.validatePurchase(REQ({ creative: {} }), ADV, NOW).errors, ['content']);
    assert.ok(s.validatePurchase(REQ({ creative: { text: 'Фақат матн' } }), ADV, NOW).ok);
    assert.strictEqual(s.orderIdOf(ADV, 'req_00000001'), s.orderIdOf(ADV, 'req_00000001'));
    assert.notStrictEqual(s.orderIdOf(ADV, 'req_00000001'), s.orderIdOf(ADV2, 'req_00000001'));
    assert.ok(/^[A-Za-z0-9_-]{2,40}$/.test(s.orderIdOf(ADV, 'req_00000001')));
  });

  await check('P2 админ созлама/тариф: рухсат, версия, аудит; сукут OFF — сотиб олиб бўлмайди', async () => {
    await expectCode(call('adminSplashAdPublishTariff', { perDay: { district: 1, region: 1, republic: 1 } }, ADV), 'PERMISSION_DENIED');
    await expectCode(call('adminSplashAdPublishTariff', { perDay: { district: 20000, region: 0, republic: 1 } }, ADMIN), 'TARIFF_INVALID');
    const info0 = await call('splashAdGetPurchaseInfo', {}, ADV);
    assert.strictEqual(info0.available, false);
    assert.strictEqual(info0.balance, 500000);
    const t1 = await call('adminSplashAdPublishTariff', { perDay: { district: 10000, region: 50000, republic: 100000 }, note: 'v1' }, ADMIN);
    assert.strictEqual(t1.version, 1);
    const t2 = await call('adminSplashAdPublishTariff', { perDay: { district: 20000, region: 60000, republic: 150000 }, note: 'v2' }, ADMIN);
    assert.strictEqual(t2.version, 2);
    assert.deepStrictEqual((await get('splash_ad_tariffs/v1')).perDay, { district: 10000, region: 50000, republic: 100000 });
    assert.strictEqual((await call('splashAdGetPurchaseInfo', {}, ADV)).available, false, 'stage off');
    await expectCode(call('splashAdQuote', REQ(), ADV), 'NOT_AVAILABLE');
    await expectCode(call('adminSplashAdSaveConfig', { config: { stage: 'everyone', internalPhones: [] } }, ADMIN), 'CONFIG_INVALID');
    await call('adminSplashAdSaveConfig', { config: { stage: 'internal', internalPhones: [ADV, ADV2] } }, ADMIN);
    const info = await call('splashAdGetPurchaseInfo', {}, ADV);
    assert.deepStrictEqual([info.available, info.tariffVersion, info.perDay.district], [true, 2, 20000]);
    assert.deepStrictEqual(info.durations, [1, 3, 5, 7]);
    const st = await call('adminSplashAdGetSettings', {}, ADMIN);
    assert.deepStrictEqual([st.config.stage, st.tariff.version, st.tariffVersions.length], ['internal', 2, 2]);
    assert.strictEqual((await audits('splash_ad_tariff_publish')).length, 2);
    assert.strictEqual((await audits('splash_ad_config')).length, 1);
  });

  let orderId;
  await check('P3 харид: сервер нархи, ҳамёндан ечиш, ledger, tariffVersion, идемпотент (retry — қайта ечмайди)', async () => {
    const q = await call('splashAdQuote', REQ(), ADV);
    assert.deepStrictEqual([q.amount, q.pricePerDay, q.tariffVersion, q.sufficient], [120000, 40000, 2, true]);
    await expectCode(call('splashAdPurchase', { ...REQ(), expectedAmount: 999 }, ADV), 'PRICE_CHANGED');
    assert.strictEqual(await bal(ADV), 500000);
    await expectCode(call('splashAdPurchase', REQ({ clientRequestId: 'x' }), ADV), 'INVALID_REQUEST');
    const r = await call('splashAdPurchase', { ...REQ(), expectedAmount: 120000 }, ADV);
    orderId = r.orderId;
    assert.deepStrictEqual([r.status, r.amount, r.tariffVersion, r.duplicate], ['pending', 120000, 2, false]);
    assert.strictEqual(await bal(ADV), 380000);
    const o = await get(`splash_ad_orders/${orderId}`);
    assert.deepStrictEqual([o.uid, o.status, o.pricePerDay, o.weight, o.days, o.areaLevel], [ADV, 'pending', 40000, 40000, 3, 'district']);
    assert.deepStrictEqual(o.districts, ['gurlan', 'urganch']);
    const led = await get(`users/${ADV}/wallet_ledger/splash_pay_${orderId}`);
    assert.strictEqual(led.amount, -120000);
    // retry (тармоқ узилди) — бир хил clientRequestId
    const again = await call('splashAdPurchase', REQ(), ADV);
    assert.deepStrictEqual([again.orderId, again.duplicate], [orderId, true]);
    const both = await Promise.all([call('splashAdPurchase', REQ(), ADV), call('splashAdPurchase', REQ(), ADV)]);
    assert.ok(both.every((x) => x.orderId === orderId));
    assert.strictEqual(await bal(ADV), 380000);
    assert.strictEqual((await db.collection('splash_ad_orders').get()).size, 1);
    // тариф кейин ўзгарса — эски буюртма нархи ўзгармайди
    await call('adminSplashAdPublishTariff', { perDay: { district: 25000, region: 60000, republic: 150000 } }, ADMIN);
    assert.strictEqual((await get(`splash_ad_orders/${orderId}`)).amount, 120000);
  });

  await check('P4 харид рад: маблағ етмайди (ҳеч нарса ёзилмайди), ҳудуд нотўғри, бегона расм, кирмаган', async () => {
    await expectCode(call('splashAdPurchase', REQ({ clientRequestId: 'poor_00000001', creative: { imageUrl: advImg(ADV2) } }), ADV2), 'INSUFFICIENT_BALANCE');
    assert.strictEqual(await bal(ADV2), 1000);
    assert.strictEqual((await db.collection('splash_ad_orders').where('uid', '==', ADV2).get()).size, 0);
    await expectCode(call('splashAdQuote', REQ({ districts: ['nowhere'] }), ADV), 'AREA_INVALID');
    await expectCode(call('splashAdQuote', REQ({ districts: ['oldone'] }), ADV), 'AREA_INVALID');
    await expectCode(call('splashAdQuote', REQ({ areaLevel: 'region', regionId: 'nowhere' }), ADV), 'AREA_INVALID');
    await expectCode(call('splashAdQuote', REQ({ creative: { imageUrl: advImg(ADV2) } }), ADV), 'INVALID_REQUEST');
    await expectCode(call('splashAdPurchase', REQ(), anonCtx('anonY')), 'UNAUTHENTICATED');
    const reg = await call('splashAdQuote', REQ({ areaLevel: 'region', regionId: 'xorazm', days: 7 }), ADV);
    assert.deepStrictEqual([reg.pricePerDay, reg.amount], [60000, 420000]);
    const rep = await call('splashAdQuote', REQ({ areaLevel: 'republic', days: 1 }), ADV);
    assert.strictEqual(rep.amount, 150000);
  });

  let order2;
  await check('P5 тасдиқ: splash_ads (оғирлик = кунлик тўлов, ҳудуд калити, телефон йўқ), идемпотент, ўтиш назорати', async () => {
    await expectCode(call('adminModerateSplashAdOrder', { orderId, decision: 'approve' }, ADV), 'PERMISSION_DENIED');
    const copies = [];
    s.testOverrides.storage = { async copyCreative() { throw new Error('storage down'); } };
    await assert.rejects(call('adminModerateSplashAdOrder', { orderId, decision: 'approve' }, ADMIN), (e) => e.details.errorCode === 'IMAGE_COPY_FAILED');
    assert.strictEqual((await get(`splash_ad_orders/${orderId}`)).status, 'pending');
    s.testOverrides.storage = {
      async copyCreative(src, id) { copies.push(src); return `https://firebasestorage.googleapis.com/v0/b/x/o/platform_images%2Fsplash_ads%2F${id}?alt=media&token=k`; },
    };
    const r = await call('adminModerateSplashAdOrder', { orderId, decision: 'approve' }, ADMIN);
    assert.deepStrictEqual(copies, [advImg(ADV)]);
    assert.deepStrictEqual([r.status, r.duplicate], ['approved', false]);
    const ad = await get(`splash_ads/${orderId}`);
    assert.deepStrictEqual([ad.visible, ad.active, ad.source, ad.weight], [true, true, 'paid', 40000]);
    assert.deepStrictEqual(ad.areaKeys, ['d:gurlan', 'd:urganch']);
    assert.ok(!JSON.stringify(ad).includes(ADV.slice(3)), 'оммавий ҳужжатда рекламачи телефони йўқ (расм ҳаволасида ҳам)');
    assert.ok(ad.imageUrl.includes(`platform_images%2Fsplash_ads%2F${orderId}`));
    assert.strictEqual((await call('adminModerateSplashAdOrder', { orderId, decision: 'approve' }, ADMIN)).duplicate, true);
    await expectCode(call('adminModerateSplashAdOrder', { orderId, decision: 'reject', reason: 'кеч' }, ADMIN), 'INVALID_TRANSITION');
    await expectCode(call('adminUpsertSplashAd', { ad: { ...AD, id: orderId } }, ADMIN), 'SPLASH_AD_PAID_READONLY');
    assert.strictEqual((await audits('splash_ad_order_approve')).length, 1);
    // муддати ўтган — тасдиқлаб бўлмайди
    const r2 = await call('splashAdPurchase', REQ({ clientRequestId: 'req_00000002', areaLevel: 'region', regionId: 'xorazm', days: 1 }), ADV);
    order2 = r2.orderId;
    await db.doc(`splash_ad_orders/${order2}`).update({ endAt: admin.firestore.Timestamp.fromMillis(NOW - 1000) });
    await expectCode(call('adminModerateSplashAdOrder', { orderId: order2, decision: 'approve' }, ADMIN), 'ORDER_EXPIRED');
  });

  await check('P6 рад: сабаб шарт, ТЎЛИҚ қайтариш (ledger + аудит), идемпотент (икки марта — бир қайтариш)', async () => {
    const before = await bal(ADV);
    const amount = (await get(`splash_ad_orders/${order2}`)).amount;
    assert.strictEqual(amount, 60000);
    await expectCode(call('adminModerateSplashAdOrder', { orderId: order2, decision: 'reject', reason: '' }, ADMIN), 'REASON_REQUIRED');
    const [a, b] = await Promise.all([
      call('adminModerateSplashAdOrder', { orderId: order2, decision: 'reject', reason: 'Расм талабга жавоб бермайди' }, ADMIN),
      call('adminModerateSplashAdOrder', { orderId: order2, decision: 'reject', reason: 'Расм талабга жавоб бермайди' }, ADMIN),
    ]);
    assert.ok([a, b].every((x) => x.status === 'rejected'));
    assert.strictEqual(await bal(ADV), before + amount);
    const o = await get(`splash_ad_orders/${order2}`);
    assert.deepStrictEqual([o.status, o.rejectReason, o.refund.wallet], ['rejected', 'Расм талабга жавоб бермайди', amount]);
    assert.strictEqual((await get(`users/${ADV}/wallet_ledger/splash_refund_${order2}`)).amount, amount);
    assert.strictEqual(await get(`splash_ads/${order2}`), undefined);
    assert.strictEqual((await audits('splash_ad_order_reject')).length, 1);
    await expectCode(call('adminModerateSplashAdOrder', { orderId: order2, decision: 'approve' }, ADMIN), 'INVALID_TRANSITION');
    const ev = (await db.collection('splash_ad_events').where('orderId', '==', order2).get()).docs.map((d) => d.data().type).sort();
    assert.deepStrictEqual(ev, ['paid', 'rejected']);
  });

  await check('P7 «Менинг рекламаларим»: фақат ўзиники, ҳолат, кўрсатишлар йиғиндиси', async () => {
    await db.doc(`splash_ad_stats/${orderId}_${today}`).set({ adId: orderId, day: today, impressions: 7 });
    await db.doc(`splash_ad_stats/${orderId}_2026-01-01`).set({ adId: orderId, day: '2026-01-01', impressions: 5 });
    const mine = await call('splashAdListMyOrders', {}, ADV);
    assert.strictEqual(mine.orders.length, 2);
    const ok = mine.orders.find((x) => x.orderId === orderId);
    assert.deepStrictEqual([ok.status, ok.impressions, ok.amount, ok.startDay], ['approved', 12, 120000, today]);
    assert.strictEqual(ok.endDay, s.dayKeyOf(s.dayStartMs(today) + 3 * 86400000 - 1));
    const rej = mine.orders.find((x) => x.orderId === order2);
    assert.deepStrictEqual([rej.status, rej.refund.wallet], ['rejected', 60000]);
    assert.strictEqual((await call('splashAdListMyOrders', {}, ADV2)).orders.length, 0);
  });

  await check('P8 муддати ўтган рекламалар visible=false (идемпотент)', async () => {
    const functions = require('firebase-functions');
    const api = s.attachSplashAds({}, {
      functions, db, admin, callerPhone: () => '', canonicalUid: (x) => x, requireCallerRoles: async () => ADMIN, notifyUserInApp: async () => {},
    });
    await call('adminUpsertSplashAd', { ad: { ...AD, id: 'old_ad', startAtMs: NOW - 5 * 86400000, endAtMs: NOW - 86400000 } }, ADMIN);
    const r = await api.runExpire(NOW);
    assert.ok(r.expired >= 1);
    assert.strictEqual((await get('splash_ads/old_ad')).visible, false);
    assert.strictEqual((await get(`splash_ads/${orderId}`)).visible, true);
    assert.strictEqual((await api.runExpire(NOW)).expired, 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
