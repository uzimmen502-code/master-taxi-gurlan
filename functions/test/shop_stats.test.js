/**
 * Сотувчи статистикаси — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-shop-stats "node test/shop_stats.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-shop-stats';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const stats = require('../shop_stats');

const db = admin.firestore();
const OWNER = '998914300001';
const ctxPhone = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const ctxAnon = (u) => ({ auth: { uid: u, token: {} } });
const rec = (data, ctx) => fns.recordShopEvent.run(data, ctx);
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const day = () => stats.dayKey();
const doc = async () => (await db.collection('shop_stats').doc(`${OWNER}_${day()}`).get()).data();

async function main() {
  await clearEmulator();
  await db.collection('tv_shops').doc(OWNER).set({ name: 'Sidabilla', ownerPhone: OWNER });
  await db.collection('businesses').doc('m1').set({ ownerId: OWNER, name: 'Kiyim', status: 'active' });
  await db.collection('businesses').doc('x1').set({ ownerId: '998914300009', name: 'Begona', status: 'active' });
  await db.collection('tv_shop_items').doc('i1').set({ ownerPhone: OWNER, title: 'Non', status: 'active' });
  await db.collection('tv_shop_items').doc('i_blk').set({ ownerPhone: OWNER, title: 'Blok', status: 'blocked' });
  await db.collection('tv_shop_items').doc('i_alien').set({ ownerPhone: '998914300009', title: 'Begona', status: 'active' });

  await check('P1 kun Toshkent vaqti bo\'yicha (UTC+5); takror belgisi xaridor ID\'sini saqlamaydi', () => {
    assert.strictEqual(stats.dayKey(Date.UTC(2026, 9, 25, 19, 30)), '20261026', '19:30 UTC = 00:30 Toshkent');
    assert.strictEqual(stats.dayKey(Date.UTC(2026, 9, 25, 18, 59)), '20261025');
    const id = stats.seenId('20261025', 'uid_secret', 'shop_view', 'x');
    assert.ok(/^20261025_[0-9a-f]{32}$/.test(id) && !id.includes('uid_secret'));
  });

  await check('S1 do\'kon ko\'rishi: bir xaridor bir kunda 1 marta; manba va yo\'nalish bo\'yicha', async () => {
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, source: 'map' }, ctxAnon('a1'))).counted, true);
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, source: 'map' }, ctxAnon('a1'))).counted, false, 'takror');
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, businessId: 'm1', source: 'product' }, ctxAnon('a1'))).counted, true, 'boshqa yo\'nalish — alohida');
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, source: 'qr' }, ctxPhone('998914300002'))).counted, true);
    const d = await doc();
    assert.deepStrictEqual([d.shopViews, d.src.map, d.src.product, d.src.qr, d.dirs.own, d.dirs.m1], [3, 1, 1, 1, 2, 1]);
    assert.strictEqual(d.ownerPhone, OWNER);
  });

  await check('S2 mahsulot ko\'rishi: faqat faol va SHU eganiki; manba, mahsulot bo\'yicha', async () => {
    assert.strictEqual((await rec({ kind: 'product_view', ownerPhone: OWNER, itemId: 'i1', source: 'market' }, ctxAnon('a2'))).counted, true);
    assert.strictEqual((await rec({ kind: 'product_view', ownerPhone: OWNER, itemId: 'i_blk', source: 'market' }, ctxAnon('a2'))).counted, false);
    assert.strictEqual((await rec({ kind: 'product_view', ownerPhone: OWNER, itemId: 'i_alien', source: 'market' }, ctxAnon('a2'))).counted, false, 'begona mahsulotni boshqa egaga yozib bo\'lmaydi');
    assert.strictEqual((await rec({ kind: 'product_view', ownerPhone: OWNER, itemId: 'yoq', source: 'market' }, ctxAnon('a2'))).counted, false);
    const d = await doc();
    assert.deepStrictEqual([d.productViews, d.items.i1, d.productSrc.market], [1, 1, 1]);
    assert.strictEqual(d.items.i_alien, undefined);
  });

  await check('S3 sanalmaydi: egasining o\'zi, loginsiz, noto\'g\'ri tur/telefon/ID, begona yo\'nalish, notanish manba -> other', async () => {
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER }, ctxPhone(OWNER))).counted, false, 'o\'zi');
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER }, {})).counted, false);
    assert.strictEqual((await rec({ kind: 'like', ownerPhone: OWNER }, ctxAnon('a3'))).counted, false);
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: '123' }, ctxAnon('a3'))).counted, false);
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, businessId: 'x1' }, ctxAnon('a3'))).counted, false, 'begona yo\'nalish');
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, businessId: '../x' }, ctxAnon('a3'))).counted, false);
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER, source: 'hack' }, ctxAnon('a4'))).counted, true);
    assert.strictEqual((await doc()).src.other, 1);
  });

  await check('S4 mavjud bo\'lmagan egaga statistika ochilmaydi; bloklangan do\'kon sanalmaydi', async () => {
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: '998914300077' }, ctxAnon('a5'))).counted, false);
    assert.strictEqual((await db.collection('shop_stats').doc(`998914300077_${day()}`).get()).exists, false);
    await db.collection('tv_shops').doc(OWNER).update({ status: 'blocked' });
    assert.strictEqual((await rec({ kind: 'shop_view', ownerPhone: OWNER }, ctxAnon('a6'))).counted, false);
    await db.collection('tv_shops').doc(OWNER).update({ status: 'active' });
  });

  await check('C1 tozalash: 3 kundan eski takror belgilari o\'chadi, yangilari qoladi', async () => {
    await db.collection('shop_stats_seen').doc('20200101_old').set({ day: '20200101' });
    const removed = await stats.cleanupSeen(db, stats.dayKey(Date.now() - 3 * 86400000));
    assert.strictEqual(removed, 1);
    assert.ok(!(await db.collection('shop_stats_seen').get()).empty, 'bugungilari qoladi');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
