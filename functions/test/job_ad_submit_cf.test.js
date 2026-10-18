/**
 * «Иш топ» эълон яратиш (`submitJobAd`) — ҲАҚИҚИЙ функция, Firestore Emulator.
 *
 *   npm run test:job-ad-submit-cf   (functions/ ичидан)
 *
 * Қулфланади (аудит B6 + B8, 2026-10-18):
 *   J1  эълон яратилади; ном ва ҳудуд ёрлиғи ПРОФИЛДАН — мижоз юборган
 *       `authorName`/`address` (уй манзили, сохта ном) ҳисобга олинмайди
 *   J2  ҳудуд ёзилмаган профил: `address` бўш, эълон барибир яратилади
 *   J3  IDEMPOTENT: бир хил `requestId` иккинчи марта — янги эълон ЙЎҚ, `duplicate`
 *   J4  бошқа `requestId` — алоҳида эълон; яроқсиз (қисқа) `requestId` — идемпотент эмас
 *   J5  бошқа фойдаланувчи ўша `requestId` билан — ўз эълонини яратади
 *   J6  ПОЙГА: бир хил `requestId` билан икки параллел чақирув — битта эълон
 *   J7  кунлик лимит: 10 дан кейин `JOB_AD_DAILY_LIMIT`; охиргисининг ўша `requestId`
 *       билан қайта юборилиши хато ЭМАС (дубликат)
 *   J8  лимит "куни" — Тошкент куни (кеча 23:30 Тошкент вақти ҳисобга кирмайди)
 *   J9  хатолар диагностик код билан (`details.code`)
 *   J10 autoApprove ёқилган — `active`
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-job-ad-submit';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const crypto = require('crypto');
const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

const A = '998901110001';
const B = '998901110002';
const NOGEO = '998901110003';

const ctx = (phone) => ({ auth: { uid: phone, token: { phone_number: `+${phone}` } } });
const call = (data, phone) => fns.submitJobAd.run(data, ctx(phone));
const rid = () => crypto.randomUUID();
const payload = (extra = {}) => ({
  type: 'ad', title: 'Ноутбук сотилади', text: 'Ҳолати аъло', isUrgent: false, ...extra,
});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function rejectsWith(promise, errorCode, fbCode) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.details && e.details.code, errorCode,
      `kutilgan kod ${errorCode}, keldi ${e.details && e.details.code} (${e.message})`);
    if (fbCode) assert.strictEqual(e.code, fbCode);
    return;
  }
  assert.fail(`${errorCode} bilan rad etilishi kerak edi`);
}

async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => db.recursiveDelete(d.ref)));
}
async function reset() {
  await Promise.all(['users', 'ads', 'settings', 'geo_districts', 'geo_regions'].map(wipe));
  // Ҳақиқий ҳужжатлардаги каби: `name` — лотин, `nameUz` — кирилл.
  await db.doc('geo_regions/xorazm').set({ name: 'Xorazm viloyati', nameUz: 'Хоразм вилояти' });
  await db.doc('geo_districts/gurlan').set({
    name: 'Gurlan tumani', nameUz: 'Гурлан тумани', regionId: 'xorazm',
  });
  await db.doc(`users/${A}`).set({ name: 'Али Валиев', districtId: 'gurlan', regionId: 'xorazm' });
  await db.doc(`users/${B}`).set({ name: 'Вали', districtId: 'gurlan', regionId: 'xorazm' });
  await db.doc(`users/${NOGEO}`).set({ name: 'Гео йўқ' });
}
const adsOf = async (phone) =>
  (await db.collection('ads').where('authorPhone', '==', phone).get()).docs;

/** Тошкент кунининг боши (тест ўзи мустақил ҳисоблайди). */
function tashkentStartMs(now = Date.now()) {
  const off = 5 * 3600 * 1000;
  const shifted = now + off;
  return shifted - (shifted % 86400000) - off;
}
async function seedAds(phone, n, createdMs) {
  await Promise.all(Array.from({ length: n }, (_, i) =>
    db.collection('ads').doc(`seed_${phone}_${createdMs}_${i}`).set({
      type: 'ad', authorPhone: phone, status: 'active', title: 'x', text: 'x',
      createdAt: admin.firestore.Timestamp.fromMillis(createdMs),
    })));
}

(async () => {
  await reset();
  await check('J1 ном/ҳудуд профилдан; мижознинг authorName/address ҳисобга олинмайди', async () => {
    const r = await call(payload({
      requestId: rid(), authorName: 'САХТА НОМ',
      address: 'Гурлан, Навоий кўчаси 12-уй, 4-хона',
    }), A);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.status, 'pending');
    const d = (await db.doc(`ads/${r.adId}`).get()).data();
    assert.strictEqual(d.authorName, 'Али Валиев');
    assert.strictEqual(d.address, 'Гурлан тумани, Хоразм вилояти');
    assert.ok(!/Навоий|12-уй/.test(JSON.stringify(d)), 'уй манзили ҳужжатга тушмаслиги керак');
    assert.strictEqual(d.districtId, 'gurlan');
    assert.strictEqual(d.regionId, 'xorazm');
    assert.strictEqual(d.authorPhone, A);
  });

  await reset();
  await check('J2 ҳудуд ёзилмаган профил: address бўш, эълон яратилади', async () => {
    const r = await call(payload({ requestId: rid(), address: 'Уй манзили' }), NOGEO);
    const d = (await db.doc(`ads/${r.adId}`).get()).data();
    assert.strictEqual(d.address, '');
    assert.strictEqual(d.authorName, 'Гео йўқ');
    assert.ok(d.districtId === undefined);
  });

  await reset();
  await check('J3 IDEMPOTENT: бир хил requestId — иккинчи эълон яратилмайди', async () => {
    const id = rid();
    const r1 = await call(payload({ requestId: id }), A);
    const r2 = await call(payload({ requestId: id }), A);
    assert.strictEqual(r2.adId, r1.adId);
    assert.strictEqual(r2.duplicate, true);
    assert.strictEqual(r1.duplicate, undefined);
    assert.strictEqual((await adsOf(A)).length, 1);
  });

  await reset();
  await check('J4 бошқа requestId — алоҳида эълон; яроқсиз requestId — идемпотент эмас', async () => {
    await call(payload({ requestId: rid() }), A);
    await call(payload({ requestId: rid() }), A);
    assert.strictEqual((await adsOf(A)).length, 2);
    await call(payload({ requestId: 'short' }), A);
    await call(payload({ requestId: 'short' }), A);
    assert.strictEqual((await adsOf(A)).length, 4);
    await call(payload(), A);
    await call(payload(), A);
    assert.strictEqual((await adsOf(A)).length, 6);
  });

  await reset();
  await check('J5 бошқа фойдаланувчи ўша requestId билан ўз эълонини яратади', async () => {
    const id = rid();
    const ra = await call(payload({ requestId: id }), A);
    const rb = await call(payload({ requestId: id }), B);
    assert.notStrictEqual(ra.adId, rb.adId);
    assert.strictEqual((await adsOf(A)).length, 1);
    assert.strictEqual((await adsOf(B)).length, 1);
  });

  await reset();
  await check('J6 ПОЙГА: бир хил requestId билан икки параллел чақирув — битта эълон', async () => {
    const id = rid();
    const out = await Promise.all([call(payload({ requestId: id }), A), call(payload({ requestId: id }), A)]);
    assert.strictEqual(out[0].adId, out[1].adId);
    assert.strictEqual((await adsOf(A)).length, 1);
  });

  await reset();
  await check('J7 кунлик лимит 10; охиргисини қайта юбориш хато эмас', async () => {
    const ids = Array.from({ length: 10 }, rid);
    for (const id of ids) await call(payload({ requestId: id }), A);
    assert.strictEqual((await adsOf(A)).length, 10);
    await rejectsWith(call(payload({ requestId: rid() }), A), 'JOB_AD_DAILY_LIMIT', 'resource-exhausted');
    const again = await call(payload({ requestId: ids[9] }), A);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual((await adsOf(A)).length, 10);
  });

  await reset();
  await check('J8 лимит куни — Тошкент куни: кеча 23:30 (Тошкент) ҳисобга кирмайди, бугунги кирмайди', async () => {
    const start = tashkentStartMs();
    await seedAds(A, 10, start - 30 * 60 * 1000); // кеча 23:30 Тошкент
    const r = await call(payload({ requestId: rid() }), A);
    assert.strictEqual(r.ok, true, 'кечаги эълонлар бугунги лимитга кирмаслиги керак');
    await seedAds(B, 10, start + 1000); // бугун 00:00:01 Тошкент
    await rejectsWith(call(payload({ requestId: rid() }), B), 'JOB_AD_DAILY_LIMIT');
  });

  await reset();
  await check('J9 хатолар диагностик код билан (details.code)', async () => {
    await rejectsWith(call(payload({ type: 'bogus' }), A), 'JOB_AD_INVALID_TYPE', 'invalid-argument');
    await rejectsWith(call(payload({ title: 'ab' }), A), 'JOB_AD_TITLE_LENGTH', 'invalid-argument');
    await rejectsWith(call(payload({ text: 'ab' }), A), 'JOB_AD_TEXT_LENGTH', 'invalid-argument');
    await rejectsWith(fns.submitJobAd.run(payload(), {}), 'UNAUTHENTICATED', 'unauthenticated');
    assert.strictEqual((await adsOf(A)).length, 0);
  });

  await reset();
  await check('J10 autoApprove ёқилган — active', async () => {
    await db.doc('settings/app').set({ jobsAutoApprove: true });
    const r = await call(payload({ requestId: rid() }), A);
    assert.strictEqual(r.status, 'active');
    const d = (await db.doc(`ads/${r.adId}`).get()).data();
    assert.strictEqual(d.moderatedBy, 'auto');
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
