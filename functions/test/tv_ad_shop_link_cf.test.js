/**
 * `publishTvAd` — ихтиёрий `shopItemId` (Бизнес харитаси «Реклама қилиш»: реклама клипи каталог маҳсулотига боғланади),
 * Firestore Emulator, ҲАҚИҚИЙ `functions/index.js` ва ledger.
 *
 *   firebase emulators:exec --only firestore --project demo-tv-ad-link \
 *     "node test/tv_ad_shop_link_cf.test.js"
 *
 * Инвариантлар: боғланиш ТЎЛОВДАН ОЛДИН текширилади (яроқсиз маҳсулот — пул ечилмайди, клип яратилмайди);
 * мижозга ишонилмайди (бегона/ўчирилган/блокланган/кутилаётган маҳсулот рад); `shopItemId`сиз чақирув аввалгидек.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-tv-ad-link';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index.js');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');

const db = admin.firestore();
const BUYER = '998901000001';
const OTHER = '998901000002';
const START = 500000;
const PRICE = 20000;
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const ad = (extra = {}) => ({
  idempotencyKey: `k_${Math.random().toString(36).slice(2, 10)}`,
  durationDays: 7, tier: 'basic', scope: 'district', videoUrl: 'https://x/v.m3u8', title: 'Non reklamasi', ...extra,
});

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
async function reset() {
  await Promise.all(['users', 'settings', 'tv_clips', 'tv_shop_items', 'wallet_idempotency', ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  await db.doc('settings/app').set({ tvAdPricing: { basic: { 7: PRICE } } });
  for (const uid of [BUYER, OTHER]) {
    await db.collection('users').doc(uid).set({ role: 'user', phone: uid, bonusBalance: START });
    await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid))
        .set({ type: 'liability', ownerUid: uid, balance: START });
  }
  const item = (o) => ({ ownerPhone: BUYER, title: 'Non', price: 5000, status: 'active', kind: 'product', clipIds: ['own_clip'], ...o });
  await db.collection('tv_shop_items').doc('i_ok').set(item({ businessId: 'b1' }));
  await db.collection('tv_shop_items').doc('i_plain').set(item({}));
  await db.collection('tv_shop_items').doc('i_alien').set(item({ ownerPhone: OTHER }));
  await db.collection('tv_shop_items').doc('i_deleted').set(item({ status: 'deleted' }));
  await db.collection('tv_shop_items').doc('i_blocked').set(item({ status: 'blocked' }));
  await db.collection('tv_shop_items').doc('i_pending').set(item({ status: 'pending' }));
}
const bal = async (uid) => (await db.collection('users').doc(uid).get()).data().bonusBalance;
const clips = async () => (await db.collection('tv_clips').get()).docs.map((d) => ({ id: d.id, ...d.data() }));
const idemCount = async () => (await db.collection('wallet_idempotency').get()).size;
async function rejectsWith(promise, code, detailCode) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    if (detailCode) assert.strictEqual(e.details && e.details.code, detailCode, 'details.code');
    return;
  }
  throw new Error(`kutilgan ${code}, lekin muvaffaqiyatli bajarildi`);
}

(async () => {
  await reset();
  await check('L1 o\'z faol mahsulotiga boglash: klipda shopItemId, pul bir marta yechiladi, mahsulotning clipIds i o\'zgarmaydi', async () => {
    const r = await fns.publishTvAd.run(ad({ shopItemId: 'i_ok' }), ctxOf(BUYER));
    assert.strictEqual(r.ok, true);
    const c = (await clips()).find((x) => x.id === r.clipId);
    assert.strictEqual(c.shopItemId, 'i_ok');
    assert.strictEqual(c.category, 'ad');
    assert.strictEqual(c.ownerPhone, BUYER);
    assert.strictEqual(await bal(BUYER), START - PRICE);
    const item = (await db.doc('tv_shop_items/i_ok').get()).data();
    assert.deepStrictEqual(item.clipIds, ['own_clip'], 'vaqtinchalik reklama mahsulotning video ro\'yxatiga qo\'shilmaydi');
    assert.strictEqual(item.status, 'active');
  });

  await reset();
  await check('L2 oddiy (businessId siz) o\'z mahsulotiga ham boglanadi; shopItemId siz chaqiruv avvalgidek — maydon yozilmaydi', async () => {
    const a = await fns.publishTvAd.run(ad({ shopItemId: 'i_plain' }), ctxOf(BUYER));
    const b = await fns.publishTvAd.run(ad(), ctxOf(BUYER));
    const all = await clips();
    assert.strictEqual(all.find((x) => x.id === a.clipId).shopItemId, 'i_plain');
    assert.ok(!('shopItemId' in all.find((x) => x.id === b.clipId)), 'shopItemId yo\'q');
    assert.strictEqual(await bal(BUYER), START - 2 * PRICE);
  });

  await reset();
  await check('L3 yaroqsiz mahsulot — SHOP_ITEM_INVALID, PUL YECHILMAYDI, klip va idempotency yozuvi yo\'q (begona/o\'chirilgan/bloklangan/kutilayotgan/yo\'q)', async () => {
    for (const id of ['i_alien', 'i_deleted', 'i_blocked', 'i_pending', 'i_yoq']) {
      await rejectsWith(fns.publishTvAd.run(ad({ shopItemId: id }), ctxOf(BUYER)), 'failed-precondition', 'SHOP_ITEM_INVALID');
    }
    assert.strictEqual(await bal(BUYER), START, 'pul o\'zgarmagan');
    assert.strictEqual((await clips()).length, 0);
    assert.strictEqual(await idemCount(), 0);
    const journal = await db.collection(ledger.COL_JOURNAL).get();
    assert.strictEqual(journal.size, 0, 'ledger bo\'sh');
  });

  await reset();
  await check('L4 shopItemId formati yaroqsiz (yo\'l belgilari, juda uzun) — invalid-argument, pul yechilmaydi', async () => {
    for (const id of ['../x', 'a/b', 'x'.repeat(129), 'a b']) {
      await rejectsWith(fns.publishTvAd.run(ad({ shopItemId: id }), ctxOf(BUYER)), 'invalid-argument', 'SHOP_ITEM_INVALID');
    }
    assert.strictEqual(await bal(BUYER), START);
    assert.strictEqual((await clips()).length, 0);
  });

  await reset();
  await check('L5 boshqa foydalanuvchi bu mahsulotga reklama bog\'lay olmaydi (egasi tekshiriladi)', async () => {
    await rejectsWith(fns.publishTvAd.run(ad({ shopItemId: 'i_ok' }), ctxOf(OTHER)), 'failed-precondition', 'SHOP_ITEM_INVALID');
    assert.strictEqual(await bal(OTHER), START);
  });

  await reset();
  await check('L6 takroriy chaqiruv (shu kalit) — bitta klip, bitta yechish, natija bir xil', async () => {
    const data = ad({ idempotencyKey: 'k_link_retry', shopItemId: 'i_ok' });
    const r1 = await fns.publishTvAd.run(data, ctxOf(BUYER));
    const r2 = await fns.publishTvAd.run(data, ctxOf(BUYER));
    assert.strictEqual(r2.clipId, r1.clipId);
    assert.strictEqual((await clips()).length, 1);
    assert.strictEqual(await bal(BUYER), START - PRICE);
  });

  await reset();
  await check('L7 balans yetmasa ham boglangan mahsulot bilan hech narsa yozilmaydi', async () => {
    await db.collection('users').doc(BUYER).update({ bonusBalance: 100 });
    await rejectsWith(fns.publishTvAd.run(ad({ shopItemId: 'i_ok' }), ctxOf(BUYER)), 'failed-precondition');
    assert.strictEqual(await bal(BUYER), 100);
    assert.strictEqual((await clips()).length, 0);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
