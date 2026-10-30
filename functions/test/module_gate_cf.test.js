/**
 * Аудит 2026-10-31: MEDIUM-4 (модул дарвозаси серверда), MEDIUM-2/5 (қайта модерация),
 * C-2 (яратиш callable'лари идемпотентлиги) — ҲАҚИҚИЙ функциялар, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-module-gate \
 *     "node functions/test/module_gate_cf.test.js"
 *
 * Қулфланади:
 *   P*  `computeModuleStatus` — клиент `ServiceConfigHolder.statusOf` нусхаси (enforce true/false,
 *       қатламлар тартиби, manualModules фильтри, номаълум статус → hidden)
 *   G*  `moduleOpenFor`: конфиг йўқ → очиқ; туман/MFY override; service_areas орқали туман;
 *       ўқиш хатоси → FAIL-OPEN; 60 с кэш
 *   B*  upsertMyBusiness (`business_map`): ёпиқ → MODULE_CLOSED; таҳрир ва дубликат — тўсилмайди
 *   J*  submitJobAd (`jobs`): ёпиқ → MODULE_CLOSED; ўша requestId дубликати — тўсилмайди
 *   M*  submitMarketAd (`cheap_products_home`): ёпиқ → MODULE_CLOSED; requestId идемпотентлиги
 *   R*  restaurantRegister (`restaurants`): ёпиқ → MODULE_CLOSED; requestId идемпотентлиги
 *   A*  onAdUpdate: бозор эълони контенти ўзгарса → pending (фақат ҚЎЛДА режим, фақат 4 калит)
 *   T*  onTvClipVideoReplacedV2: клип ном/тавсиф/муқоваси ўзгарса → pending (content_edited)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-module-gate';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const crypto = require('crypto');
const fns = require('../index');
const admin = require('firebase-admin');
const gateMod = require('../module_gate');
const { tvClipContentEdited } = require('../tv_clip_moderation');

const db = admin.firestore();

const U_GURLAN = '998931000001'; // users.districtId = gurlan
const U_OTHER = '998931000002'; // users.districtId = xiva
const U_AREA = '998931000003'; // faqat serviceAreaId (districtId yo'q) → service_areas/area_g.districtId = gurlan
const U_NOGEO = '998931000004';
const U_LEGACY9 = '931000005'; // eski 9 xonali users hujjati (token 998931000005)
const ALL = [U_GURLAN, U_OTHER, U_AREA, U_NOGEO];

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
const rid = () => crypto.randomUUID();

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}

/** Prod'га ўхшаш: enforce=true, keltirilgan modullar global holati. */
async function setDefaults(modules, enforce = true) {
  const m = {};
  for (const [k, v] of Object.entries(modules)) m[k] = { status: v };
  await db.doc('config/module_defaults').set({ enforce, modules: m });
  gateMod.resetCache();
}
async function setDistrict(id, modules, manual = Object.keys(modules)) {
  const m = {};
  for (const [k, v] of Object.entries(modules)) m[k] = { status: v };
  await db.doc(`geo_district_modules/${id}`).set({ districtId: id, modules: m, manualModules: manual });
  gateMod.resetCache();
}

async function reset() {
  await clearEmulator();
  gateMod.resetCache();
  await db.doc('geo_regions/xorazm').set({ name: 'Xorazm', nameUz: 'Хоразм' });
  await db.doc('geo_districts/gurlan').set({ name: 'Gurlan', nameUz: 'Гурлан', regionId: 'xorazm' });
  await db.doc('geo_districts/xiva').set({ name: 'Xiva', nameUz: 'Хива', regionId: 'xorazm' });
  await db.doc('service_areas/area_g').set({ districtId: 'gurlan', regionId: 'xorazm' });
  await db.doc(`users/${U_GURLAN}`).set({ role: 'user', name: 'G', districtId: 'gurlan', regionId: 'xorazm' });
  await db.doc(`users/${U_OTHER}`).set({ role: 'user', name: 'O', districtId: 'xiva', regionId: 'xorazm' });
  await db.doc(`users/${U_AREA}`).set({ role: 'user', name: 'A', serviceAreaId: 'area_g' });
  await db.doc(`users/${U_NOGEO}`).set({ role: 'user', name: 'N' });
  await db.doc(`users/${U_LEGACY9}`).set({ role: 'user', name: 'L', districtId: 'gurlan' });
  await db.doc('module_config/restaurants_all').set({ restaurants: { stage: 'public', testerIds: [] } });
  await db.doc('settings/app').set({
    restaurantAutoApprove: false, jobsAutoApprove: false, marketAutoApprove: false, tvAutoApprove: false,
  });
}

const BIZ = {
  name: 'Gurlan Avto-moyka', category: 'auto', phone: '+998 90 123-45-67',
  address: 'Gurlan, Navoiy 5', lat: 41.8442, lng: 60.3925,
};
const JOB = { type: 'ad', title: 'Ноутбук сотилади', text: 'Ҳолати аъло' };
const marketAd = (who, extra = {}) => ({
  title: 'Velosiped', description: 'Yaxshi holatda', price: 350000,
  imageUrls: [`https://firebasestorage.googleapis.com/v0/b/x/o/ads%2F${who}%2F1.jpg`], ...extra,
});
const REST = {
  name: 'Gurlan osh', legalType: 'yatt', address: 'Gurlan, markaz', lat: 41.8406, lng: 60.3917,
  delivery: { mode: 'none', pickup: true },
};
const count = async (col, field, val) => (await db.collection(col).where(field, '==', val).get()).size;

async function main() {
  // ── P: sof hisob ─────────────────────────────────────────────────────
  const { computeModuleStatus: cs, configFromMap, overrideFromDoc, statusFromWire } = gateMod;
  await check('P1 statusFromWire: Dart fromWire bilan bir xil (noma\'lum → hidden)', () => {
    assert.strictEqual(statusFromWire('enabled'), 'enabled');
    assert.strictEqual(statusFromWire(' TRUE '), 'enabled');
    assert.strictEqual(statusFromWire('comingSoon'), 'coming_soon');
    assert.strictEqual(statusFromWire('soon'), 'soon');
    assert.strictEqual(statusFromWire('disabled'), 'hidden');
    assert.strictEqual(statusFromWire(undefined), 'hidden');
    assert.strictEqual(statusFromWire('xyz'), 'hidden');
  });
  await check('P2 enforce=true: defaults → district → area ustunligi; topilmasa hidden', () => {
    const L = { enforce: true, defaults: { jobs: 'soon', courier: 'enabled' }, district: { jobs: 'enabled' }, area: { jobs: 'hidden' } };
    assert.strictEqual(cs(L, 'jobs'), 'hidden'); // area eng ustun
    assert.strictEqual(cs({ ...L, area: {} }, 'jobs'), 'enabled');
    assert.strictEqual(cs({ ...L, area: {}, district: {} }, 'jobs'), 'soon');
    assert.strictEqual(cs(L, 'courier'), 'enabled');
    assert.strictEqual(cs(L, 'restaurants'), 'hidden');
    assert.strictEqual(cs({ enforce: true, defaults: {}, district: {}, area: {} }, 'jobs'), 'hidden');
  });
  await check('P3 enforce=false: biror qatlamda bor → enabled (holatidan qat\'i nazar), yo\'q → hidden', () => {
    const L = { enforce: false, defaults: { jobs: 'soon' }, district: { courier: 'hidden' }, area: {} };
    assert.strictEqual(cs(L, 'jobs'), 'enabled');
    assert.strictEqual(cs(L, 'courier'), 'enabled');
    assert.strictEqual(cs(L, 'restaurants'), 'hidden');
  });
  await check('P4 fromMap: `modules` map / sodda satr shakli; override faqat manualModules', () => {
    assert.deepStrictEqual(configFromMap({ modules: { a: { status: 'soon' }, b: 'enabled' } }), { a: 'soon', b: 'enabled' });
    assert.deepStrictEqual(configFromMap({}), {});
    assert.deepStrictEqual(overrideFromDoc({ modules: { a: { status: 'enabled' }, b: { status: 'enabled' } } }), {});
    assert.deepStrictEqual(overrideFromDoc({ modules: { a: { status: 'enabled' }, b: { status: 'soon' } }, manualModules: ['b', 'z'] }), { b: 'soon' });
  });

  // ── G: moduleOpenFor ─────────────────────────────────────────────────
  await reset();
  await check('G1 config/module_defaults YO\'Q → ochiq (CONFIG_MISSING, yaratish ishlaydi)', async () => {
    const g = await gateMod.moduleOpenFor(db, 'jobs', U_GURLAN);
    assert.deepStrictEqual(g, { open: true, status: 'unknown', reason: 'CONFIG_MISSING' });
    const r = await call('submitJobAd', { ...JOB, requestId: rid() }, U_GURLAN);
    assert.strictEqual(r.ok, true);
  });
  await check('G2 global soon + gurlan override enabled: gurlan ochiq, xiva va hududsiz yopiq', async () => {
    await setDefaults({ jobs: 'soon' });
    await setDistrict('gurlan', { jobs: 'enabled' });
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_GURLAN)).open, true);
    assert.deepStrictEqual(await gateMod.moduleOpenFor(db, 'jobs', U_OTHER), { open: false, status: 'soon', reason: 'MODULE_CLOSED' });
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_NOGEO)).open, false);
  });
  await check('G3 districtId yo\'q, serviceAreaId bor → service_areas orqali tuman override', async () => {
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_AREA)).open, true);
  });
  await check('G4 eski 9 xonali users hujjati ham o\'qiladi', async () => {
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', `998${U_LEGACY9}`)).open, true);
  });
  await check('G5 manualModules\'da YO\'Q override e\'tiborsiz (eski seed)', async () => {
    await setDistrict('xiva', { jobs: 'enabled' }, []);
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_OTHER)).open, false);
  });
  await check('G6 MFY (service_area_modules) override tuman ustidan', async () => {
    await db.doc('service_area_modules/area_g').set({ modules: { jobs: { status: 'hidden' } }, manualModules: ['jobs'] });
    gateMod.resetCache();
    assert.deepStrictEqual(await gateMod.moduleOpenFor(db, 'jobs', U_AREA), { open: false, status: 'hidden', reason: 'MODULE_CLOSED' });
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_GURLAN)).open, true); // MFY'siz foydalanuvchi
  });
  await check('G7 enforce=false: konfigdagi modul ochiq (soon bo\'lsa ham), konfigda yo\'q — yopiq', async () => {
    await db.doc('service_area_modules/area_g').delete();
    await setDefaults({ jobs: 'soon' }, false);
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_OTHER)).open, true);
    assert.deepStrictEqual(await gateMod.moduleOpenFor(db, 'restaurants', U_OTHER), { open: false, status: 'hidden', reason: 'MODULE_CLOSED' });
  });
  await check('G8 o\'qish xatosi → FAIL-OPEN (CONFIG_READ_FAILED), xato tashlanmaydi', async () => {
    gateMod.resetCache();
    const broken = { collection: () => ({ doc: () => ({ get: async () => { throw new Error('UNAVAILABLE: transient'); } }) }) };
    const warns = [];
    const orig = console.warn;
    console.warn = (s) => warns.push(String(s));
    try {
      assert.deepStrictEqual(await gateMod.moduleOpenFor(broken, 'jobs', U_GURLAN), { open: true, status: 'unknown', reason: 'CONFIG_READ_FAILED' });
    } finally { console.warn = orig; }
    assert.ok(warns.some((w) => /"errorCode":"CONFIG_READ_FAILED"/.test(w) && /"severity":"WARNING"/.test(w)), 'structured warning');
    assert.ok(!warns.some((w) => w.includes(U_GURLAN)), 'telefon logga chiqmaydi');
  });
  await check('G9 kesh 60 s: TTL ichida eski holat, TTL dan keyin yangisi (chegara)', async () => {
    await setDefaults({ jobs: 'enabled' });
    const t0 = Date.now();
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_OTHER, { nowMs: t0 })).open, true);
    await db.doc('config/module_defaults').set({ enforce: true, modules: { jobs: { status: 'hidden' } } });
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_OTHER, { nowMs: t0 + gateMod.CACHE_TTL_MS - 1 })).open, true);
    assert.strictEqual((await gateMod.moduleOpenFor(db, 'jobs', U_OTHER, { nowMs: t0 + gateMod.CACHE_TTL_MS })).open, false);
  });

  // ── B: upsertMyBusiness ──────────────────────────────────────────────
  await reset();
  await check('B1 business_map enabled → yaratiladi', async () => {
    await setDefaults({ business_map: 'enabled' });
    const r = await call('upsertMyBusiness', { ...BIZ, clientRequestId: 'gate-0000001' }, U_GURLAN);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.duplicate, false);
  });
  await check('B2 business_map soon/hidden → MODULE_CLOSED, hech narsa yozilmaydi', async () => {
    for (const st of ['soon', 'coming_soon', 'hidden']) {
      await setDefaults({ business_map: st });
      await expectCode(call('upsertMyBusiness', { ...BIZ, clientRequestId: `gate-${st}-02` }, U_OTHER), 'MODULE_CLOSED', 'failed-precondition');
    }
    assert.strictEqual(await count('businesses', 'ownerId', U_OTHER), 0);
  });
  await check('B3 yopiq modulda: mavjud obyektni TAHRIRLASH va o\'sha clientRequestId QAYTA yuborish — ruxsat', async () => {
    const edit = await call('upsertMyBusiness', { ...BIZ, businessId: `${U_GURLAN}_gate-0000001`, name: 'Yangi nom' }, U_GURLAN);
    assert.strictEqual(edit.changed, true);
    const again = await call('upsertMyBusiness', { ...BIZ, clientRequestId: 'gate-0000001' }, U_GURLAN);
    assert.strictEqual(again.duplicate, true);
    const del = await call('deleteMyBusiness', { businessId: `${U_GURLAN}_gate-0000001` }, U_GURLAN);
    assert.strictEqual(del.deleted, true);
  });
  await check('B4 global hidden + gurlan override enabled → gurlanlik yaratadi, xivalik yo\'q', async () => {
    await setDistrict('gurlan', { business_map: 'enabled' });
    const r = await call('upsertMyBusiness', { ...BIZ, clientRequestId: 'gate-0000004' }, U_GURLAN);
    assert.strictEqual(r.duplicate, false);
    await expectCode(call('upsertMyBusiness', { ...BIZ, clientRequestId: 'gate-0000005' }, U_OTHER), 'MODULE_CLOSED');
  });

  // ── J: submitJobAd ───────────────────────────────────────────────────
  await reset();
  await check('J1 jobs enabled → OK; soon → MODULE_CLOSED (details.code)', async () => {
    await setDefaults({ jobs: 'enabled' });
    const id = rid();
    const r = await call('submitJobAd', { ...JOB, requestId: id }, U_OTHER);
    assert.strictEqual(r.ok, true);
    await setDefaults({ jobs: 'soon' });
    await expectCode(call('submitJobAd', { ...JOB, requestId: rid() }, U_OTHER), 'MODULE_CLOSED', 'failed-precondition');
    await expectCode(call('submitJobAd', { ...JOB }, U_OTHER), 'MODULE_CLOSED'); // requestId'siz (eski APK) ham
    // Yopiq modulda o'sha requestId — dubliKAT (birinchi natija), xato emas.
    const again = await call('submitJobAd', { ...JOB, requestId: id }, U_OTHER);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual(again.adId, r.adId);
    assert.strictEqual(await count('ads', 'authorPhone', U_OTHER), 1);
  });
  await check('J2 enforce=false + jobs konfigda → OK', async () => {
    await setDefaults({ jobs: 'soon' }, false);
    assert.strictEqual((await call('submitJobAd', { ...JOB, requestId: rid() }, U_OTHER)).ok, true);
  });

  // ── M: submitMarketAd ────────────────────────────────────────────────
  await reset();
  await check('M1 cheap_products_home enabled: bir xil requestId ikki marta → BITTA e\'lon, birinchi natija', async () => {
    await setDefaults({ cheap_products_home: 'enabled' });
    const id = rid();
    const r1 = await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: id }, U_GURLAN);
    const r2 = await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: id }, U_GURLAN);
    assert.strictEqual(r1.status, 'pending');
    assert.strictEqual(r2.adId, r1.adId);
    assert.strictEqual(r2.duplicate, true);
    assert.strictEqual(r1.duplicate, undefined);
    assert.strictEqual(await count('ads', 'ownerId', U_GURLAN), 1);
  });
  await check('M2 boshqa requestId → ikkinchi e\'lon; requestId\'siz (eski APK) → har safar yangi; yaroqsiz (7 belgi) → idempotent emas', async () => {
    await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: rid() }, U_GURLAN);
    assert.strictEqual(await count('ads', 'ownerId', U_GURLAN), 2);
    await call('submitMarketAd', marketAd(U_GURLAN), U_GURLAN);
    await call('submitMarketAd', marketAd(U_GURLAN), U_GURLAN);
    assert.strictEqual(await count('ads', 'ownerId', U_GURLAN), 4);
    await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: 'abcdefg' }, U_GURLAN);
    await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: 'abcdefg' }, U_GURLAN);
    assert.strictEqual(await count('ads', 'ownerId', U_GURLAN), 6);
    // chegara: aynan 8 belgi — idempotent
    await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: 'abcdefgh' }, U_GURLAN);
    await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: 'abcdefgh' }, U_GURLAN);
    assert.strictEqual(await count('ads', 'ownerId', U_GURLAN), 7);
  });
  await check('M3 boshqa foydalanuvchi o\'sha requestId bilan — o\'z e\'loni', async () => {
    const id = rid();
    const a = await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: id }, U_GURLAN);
    const b = await call('submitMarketAd', { ...marketAd(U_OTHER), requestId: id }, U_OTHER);
    assert.notStrictEqual(a.adId, b.adId);
  });
  await check('M4 POYGA: bir xil requestId bilan ikki parallel chaqiruv — bitta e\'lon', async () => {
    const id = rid();
    const before = await count('ads', 'ownerId', U_OTHER);
    const out = await Promise.all([
      call('submitMarketAd', { ...marketAd(U_OTHER), requestId: id }, U_OTHER),
      call('submitMarketAd', { ...marketAd(U_OTHER), requestId: id }, U_OTHER),
    ]);
    assert.strictEqual(out[0].adId, out[1].adId);
    assert.strictEqual(await count('ads', 'ownerId', U_OTHER), before + 1);
  });
  await check('M5 hidden → MODULE_CLOSED; yopiq modulda o\'sha requestId — dublikat (xato emas)', async () => {
    const id = rid();
    const first = await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: id }, U_GURLAN);
    await setDefaults({ cheap_products_home: 'hidden' });
    await expectCode(call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: rid() }, U_GURLAN), 'MODULE_CLOSED', 'failed-precondition');
    const again = await call('submitMarketAd', { ...marketAd(U_GURLAN), requestId: id }, U_GURLAN);
    assert.strictEqual(again.adId, first.adId);
    assert.strictEqual(again.duplicate, true);
  });

  // ── R: restaurantRegister ────────────────────────────────────────────
  await reset();
  await check('R1 restaurants enabled: bir xil requestId → bitta restoran (a\'zo ham bitta)', async () => {
    await setDefaults({ restaurants: 'enabled' });
    const id = rid();
    const r1 = await call('restaurantRegister', { ...REST, requestId: id }, U_GURLAN);
    const r2 = await call('restaurantRegister', { ...REST, requestId: id }, U_GURLAN);
    assert.strictEqual(r1.status, 'applied');
    assert.strictEqual(r2.restaurantId, r1.restaurantId);
    assert.strictEqual(r2.duplicate, true);
    assert.strictEqual(await count('restaurants', 'ownerUid', U_GURLAN), 1);
    const m = await db.collection('restaurants').doc(r1.restaurantId).collection('members').get();
    assert.strictEqual(m.size, 1);
  });
  await check('R2 boshqa requestId → ikkinchi; requestId\'siz → avvalgidek har safar yangi', async () => {
    await call('restaurantRegister', { ...REST, requestId: rid() }, U_GURLAN);
    await call('restaurantRegister', REST, U_GURLAN);
    await call('restaurantRegister', REST, U_GURLAN);
    assert.strictEqual(await count('restaurants', 'ownerUid', U_GURLAN), 4);
  });
  await check('R3 POYGA: parallel ikki chaqiruv bir xil requestId — bitta restoran', async () => {
    const id = rid();
    const out = await Promise.all([
      call('restaurantRegister', { ...REST, requestId: id }, U_OTHER),
      call('restaurantRegister', { ...REST, requestId: id }, U_OTHER),
    ]);
    assert.strictEqual(out[0].restaurantId, out[1].restaurantId);
    assert.strictEqual(await count('restaurants', 'ownerUid', U_OTHER), 1);
  });
  await check('R4 restaurants soon → MODULE_CLOSED (bosqich darvozasi ochiq bo\'lsa ham)', async () => {
    await setDefaults({ restaurants: 'soon' });
    await expectCode(call('restaurantRegister', { ...REST, requestId: rid() }, U_GURLAN), 'MODULE_CLOSED', 'failed-precondition');
    assert.strictEqual(await count('restaurants', 'ownerUid', U_GURLAN), 4);
  });
  await check('R5 bosqich darvozasi (module_config) o\'zgarmadi: OFF → MODULE_OFF birinchi', async () => {
    await db.doc('module_config/restaurants_all').set({ enabled: false });
    await expectCode(call('restaurantRegister', { ...REST, requestId: rid() }, U_GURLAN), 'MODULE_OFF');
  });

  // ── A: bozor e'loni qayta moderatsiyasi ─────────────────────────────
  await reset();
  const runAdUpdate = async (id, patch) => {
    const ref = db.collection('ads').doc(id);
    const before = await ref.get();
    await ref.update(patch);
    const after = await ref.get();
    await fns.onAdUpdate.run({ before, after }, { params: { adId: id } });
    return (await ref.get()).data();
  };
  const seedMarket = (id) => db.collection('ads').doc(id).set({
    type: 'cheap_product', ownerId: U_GURLAN, status: 'active', title: 'Velosiped', description: 'Yaxshi',
    price: 350000, imageUrls: ['https://x/ads%2F1.jpg'], views: 3,
    moderatedAt: admin.firestore.Timestamp.fromMillis(1000),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60 * 86400000),
  });
  await check('A1 QO\'LDA: egasi title/description/imageUrls/price o\'zgartirsa → pending (owner_edit) + pending muddati', async () => {
    for (const [i, patch] of [{ title: 'Velosiped 2' }, { description: 'Boshqa' }, { imageUrls: ['https://x/ads%2F2.jpg'] }, { price: 350001 }].entries()) {
      const id = `ma${i}`;
      await seedMarket(id);
      const d = await runAdUpdate(id, patch);
      assert.strictEqual(d.status, 'pending', JSON.stringify(patch));
      assert.strictEqual(d.moderationReason, 'owner_edit');
    }
    // Ikkinchi trigger (active → pending) pending muddatini yozadi — mavjud zanjir.
    const ref = db.collection('ads').doc('ma0');
    const after = await ref.get();
    await fns.onAdUpdate.run({ before: { data: () => ({ ...after.data(), status: 'active' }) }, after }, { params: { adId: 'ma0' } });
    const exp = (await ref.get()).data().expiresAt.toMillis();
    assert.ok(exp < Date.now() + 40 * 86400000, 'pending TTL');
  });
  await check('A2 hisoblagich (views) / sellerName / searchTokens o\'zgarishi → active qoladi', async () => {
    await seedMarket('mb');
    assert.strictEqual((await runAdUpdate('mb', { views: 4 })).status, 'active');
    assert.strictEqual((await runAdUpdate('mb', { sellerName: 'Ali', searchTokens: ['a'] })).status, 'active');
    assert.strictEqual((await runAdUpdate('mb', { price: 350000 })).status, 'active'); // chegara: qiymat o'zgarmadi
  });
  await check('A3 admin tahriri (moderatedAt o\'zgaradi) va AVTO rejim → active qoladi', async () => {
    await seedMarket('mc');
    assert.strictEqual((await runAdUpdate('mc', { title: 'Admin tuzatdi', moderatedAt: admin.firestore.Timestamp.fromMillis(2000) })).status, 'active');
    await db.doc('settings/app').set({ marketAutoApprove: true }, { merge: true });
    assert.strictEqual((await runAdUpdate('mc', { title: 'Egasi' })).status, 'active');
  });
  await check('A4 ish e\'loni shoxi o\'zgarmadi (regressiya)', async () => {
    await db.collection('ads').doc('jj').set({ type: 'work', status: 'active', text: 'Ishchi', authorPhone: U_GURLAN, moderatedAt: admin.firestore.Timestamp.fromMillis(1000) });
    assert.strictEqual((await runAdUpdate('jj', { text: 'Boshqa' })).status, 'pending');
  });

  // ── T: TV klip qayta moderatsiyasi ───────────────────────────────────
  await reset();
  const clipBase = { status: 'active', category: 'product', ownerPhone: U_GURLAN, videoUrl: 'https://example.invalid/v1.mp4', title: 'Non', description: 'Issiq', posterUrl: 'https://example.invalid/p1.jpg' };
  const runClip = async (id, before, after) => {
    await db.collection('tv_clips').doc(id).set(after);
    const afterSnap = await db.collection('tv_clips').doc(id).get();
    await fns.onTvClipVideoReplacedV2.run({ data: { before: { data: () => before }, after: afterSnap }, params: { clipId: id } });
    return (await db.collection('tv_clips').doc(id).get()).data();
  };
  await check('T1 sof: faqat title/description/posterUrl; video o\'zgarsa — bu shox emas; ad/pending — yo\'q', () => {
    assert.strictEqual(tvClipContentEdited(clipBase, { ...clipBase, title: 'X' }), true);
    assert.strictEqual(tvClipContentEdited(clipBase, { ...clipBase, description: 'X' }), true);
    assert.strictEqual(tvClipContentEdited(clipBase, { ...clipBase, posterUrl: 'https://example.invalid/p2.jpg' }), true);
    assert.strictEqual(tvClipContentEdited(clipBase, { ...clipBase, likeCount: 5, viewCount: 9, playbackStats: { a: 1 }, hlsUrl: 'h' }), false);
    assert.strictEqual(tvClipContentEdited(clipBase, { ...clipBase, title: 'X', videoUrl: 'https://example.invalid/v2.mp4' }), false);
    assert.strictEqual(tvClipContentEdited({ ...clipBase, category: 'ad' }, { ...clipBase, category: 'ad', title: 'X' }), false);
    assert.strictEqual(tvClipContentEdited({ ...clipBase, status: 'pending' }, { ...clipBase, status: 'pending', title: 'X' }), false);
    assert.strictEqual(tvClipContentEdited({ ...clipBase, description: undefined }, { ...clipBase, description: '' }), false); // chegara
  });
  await check('T2 QO\'LDA: egasi tasdiqlangan klip nomini o\'zgartirsa → pending (content_edited)', async () => {
    const d = await runClip('t2', clipBase, { ...clipBase, title: 'Yangi non' });
    assert.strictEqual(d.status, 'pending');
    assert.strictEqual(d.moderationReason, 'content_edited');
  });
  await check('T3 o\'z yozuvi qayta ishga tushsa (active → pending) — hech narsa o\'zgarmaydi (sikl yo\'q)', async () => {
    const before = (await db.collection('tv_clips').doc('t2').get()).data();
    const d = await runClip('t2', { ...before, status: 'active', title: 'Yangi non' }, before);
    assert.strictEqual(d.status, 'pending');
    assert.strictEqual(d.moderationReason, 'content_edited');
  });
  await check('T4 hisoblagichlar / AVTO rejim → active qoladi', async () => {
    let d = await runClip('t4', clipBase, { ...clipBase, likeCount: 1, viewCount: 2, commentCount: 3 });
    assert.strictEqual(d.status, 'active');
    await db.doc('settings/app').set({ tvAutoApprove: true }, { merge: true });
    d = await runClip('t5', clipBase, { ...clipBase, title: 'Avto' });
    assert.strictEqual(d.status, 'active');
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
