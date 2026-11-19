/**
 * Маҳсулот белгиси (эга 2026-11-19) — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-product-promo "node test/product_promo_cf.test.js"
 *
 * onShopItemPromoWrite, onWholesaleProductPromoWrite, onWholesaleStockBadge, adminModeratePromo.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-product-promo';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { requestKeyOf } = require('../product_promo');

const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const TS = admin.firestore.Timestamp;
const DAY = 24 * 60 * 60 * 1000;
const ADMIN = '998915000001';
const OWNER = '998901112233';
const OTHER = '998912000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

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
const get = async (col, id) => (await db.collection(col).doc(id).get()).data();

async function writeAndRun(fnName, col, id, writeFn) {
  const ref = db.collection(col).doc(id);
  const before = await ref.get();
  await writeFn(ref);
  const after = await ref.get();
  await fns[fnName].run({ before, after }, { params: { docId: id }, timestamp: new Date().toISOString() });
  return (await ref.get()).data();
}
const shopW = (id, w) => writeAndRun('onShopItemPromoWrite', 'tv_shop_items', id, w);
const wsW = (id, w) => writeAndRun('onWholesaleProductPromoWrite', 'wholesale_products', id, w);
const moderate = (data, who = ADMIN) => fns.adminModeratePromo.run(data, ctxOf(who));
const item = (extra = {}) => ({ ownerPhone: OWNER, title: 'Qo\'y', price: 100000, status: 'active', moderatedAt: TS.now(), ...extra });
const promoReq = (extra = {}) => ({ kind: 'discount', oldPrice: 100000, until: TS.fromMillis(Date.now() + 10 * DAY), requestedAt: TS.now(), ...extra });

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(OWNER).set({ role: 'user', appLang: 'uz_Latn' });
  await db.collection('users').doc(OTHER).set({ role: 'user' });

  await check('create → priceTracked + priceSince, no firstActiveAt for pending', async () => {
    const d = await shopW('s1', (r) => r.set({ ...item({ status: 'pending' }), moderatedAt: null }));
    assert.strictEqual(d.priceTracked, 100000);
    assert.ok(d.priceSince);
    assert.ok(!d.firstActiveAt);
  });
  await check('first approval → firstActiveAt stamped', async () => {
    const d = await shopW('s1', (r) => r.update({ status: 'active', moderatedAt: TS.now() }));
    assert.ok(d.firstActiveAt);
  });
  await check('re-run on same doc → no-op (no updateTime change)', async () => {
    const ref = db.collection('tv_shop_items').doc('s1');
    const s = await ref.get();
    await fns.onShopItemPromoWrite.run({ before: s, after: s }, { params: { docId: 's1' } });
    const s2 = await ref.get();
    assert.strictEqual(s2.updateTime.toMillis(), s.updateTime.toMillis());
  });
  await check('price changed → priceSince reset, history entry', async () => {
    // eski narx 8 kun turgan (sun'iy priceSince).
    await db.collection('tv_shop_items').doc('s2').set(item({ priceTracked: 100000, priceSince: TS.fromMillis(Date.now() - 8 * DAY) }));
    const d = await shopW('s2', (r) => r.update({ price: 80000, promoRequest: promoReq() }));
    assert.strictEqual(d.priceTracked, 80000);
    assert.ok(d.priceSince.toMillis() > Date.now() - 60000);
    assert.strictEqual(d.priceHistory.length, 1);
    assert.strictEqual(d.priceHistory[0].price, 100000);
    assert.strictEqual(d.promoState.status, 'pending');
    assert.strictEqual(d.promoState.percent, 20);
    assert.ok(!d.promo);
  });
  await check('non-admin cannot moderate', async () => {
    await assert.rejects(moderate({ collection: 'tv_shop_items', id: 's2', decision: 'approve' }, OWNER));
  });
  await check('admin approve → promo active + audit + seller notified', async () => {
    const r = await moderate({ collection: 'tv_shop_items', id: 's2', decision: 'approve' });
    assert.strictEqual(r.status, 'active');
    const d = await get('tv_shop_items', 's2');
    assert.strictEqual(d.promo.kind, 'discount');
    assert.strictEqual(d.promo.percent, 20);
    assert.strictEqual(d.promo.oldPrice, 100000);
    assert.strictEqual(d.promo.approvedBy, ADMIN);
    assert.strictEqual(d.promoState.status, 'active');
    const a = (await db.collection('admin_audit').where('kind', '==', 'promo_moderation').get()).docs.map((x) => x.data());
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].decision, 'approve');
    const n = (await db.collection('admin_news').where('targetUserId', '==', OWNER).get()).docs;
    assert.ok(n.length >= 1, 'xabar');
  });
  await check('approve again → PROMO_NOT_PENDING', async () => {
    await expectCode(moderate({ collection: 'tv_shop_items', id: 's2', decision: 'approve' }), 'PROMO_NOT_PENDING');
  });
  await check('price changes after approval → discount cleared', async () => {
    const d = await shopW('s2', (r) => r.update({ price: 70000 }));
    assert.ok(!d.promo);
    assert.strictEqual(d.promoState.status, 'cleared');
    assert.strictEqual(d.promoState.reason, 'PRICE_CHANGED');
  });
  await check('6 days old price → rejected OLD_PRICE_NOT_7_DAYS', async () => {
    await db.collection('tv_shop_items').doc('s3').set(item({ priceTracked: 100000, priceSince: TS.fromMillis(Date.now() - 6 * DAY) }));
    const d = await shopW('s3', (r) => r.update({ price: 80000, promoRequest: promoReq() }));
    assert.strictEqual(d.promoState.status, 'rejected');
    assert.strictEqual(d.promoState.reason, 'OLD_PRICE_NOT_7_DAYS');
  });
  await check('until > 30 days → rejected UNTIL_TOO_FAR', async () => {
    const d = await shopW('s3', (r) => r.update({ promoRequest: { kind: 'promo', until: TS.fromMillis(Date.now() + 31 * DAY), requestedAt: TS.now() } }));
    assert.strictEqual(d.promoState.reason, 'UNTIL_TOO_FAR');
  });
  await check('Aksiya (promo) → active without moderation', async () => {
    const d = await shopW('s3', (r) => r.update({ promoRequest: { kind: 'promo', until: TS.fromMillis(Date.now() + 5 * DAY), requestedAt: TS.now() } }));
    assert.strictEqual(d.promo.kind, 'promo');
    assert.strictEqual(d.promoState.status, 'active');
  });
  await check('cancel (delete request) → badge removed', async () => {
    const d = await shopW('s3', (r) => r.update({ promoRequest: FV.delete() }));
    assert.ok(!d.promo);
    assert.strictEqual(d.promoState.reason, 'CANCELLED');
  });
  await check('admin reject requires reason; reject → rejected + audit', async () => {
    await db.collection('tv_shop_items').doc('s4').set(item({ priceTracked: 100000, priceSince: TS.fromMillis(Date.now() - 9 * DAY) }));
    await shopW('s4', (r) => r.update({ price: 90000, promoRequest: promoReq() }));
    await expectCode(moderate({ collection: 'tv_shop_items', id: 's4', decision: 'reject' }), 'REASON_REQUIRED');
    const r = await moderate({ collection: 'tv_shop_items', id: 's4', decision: 'reject', reason: 'Eski narx shubhali' });
    assert.strictEqual(r.status, 'rejected');
    const d = await get('tv_shop_items', 's4');
    assert.strictEqual(d.promoState.status, 'rejected');
    assert.strictEqual(d.promoState.reason, 'ADMIN_REJECTED');
    assert.ok(!d.promo);
  });
  await check('approve when price changed before trigger → auto reject PRICE_CHANGED', async () => {
    await db.collection('tv_shop_items').doc('s5').set(item({ priceTracked: 100000, priceSince: TS.fromMillis(Date.now() - 9 * DAY) }));
    await shopW('s5', (r) => r.update({ price: 90000, promoRequest: promoReq() }));
    await db.collection('tv_shop_items').doc('s5').update({ price: 85000 }); // trigger hali ishlamagan
    const r = await moderate({ collection: 'tv_shop_items', id: 's5', decision: 'approve' });
    assert.strictEqual(r.status, 'rejected');
    assert.strictEqual(r.reason, 'PRICE_CHANGED');
  });
  await check('stale request (seller changed it) → PROMO_STALE', async () => {
    await db.collection('tv_shop_items').doc('s6').set(item({ priceTracked: 100000, priceSince: TS.fromMillis(Date.now() - 9 * DAY) }));
    await shopW('s6', (r) => r.update({ price: 90000, promoRequest: promoReq() }));
    await db.collection('tv_shop_items').doc('s6').update({ 'promoRequest.until': TS.fromMillis(Date.now() + 3 * DAY) });
    await expectCode(moderate({ collection: 'tv_shop_items', id: 's6', decision: 'approve' }), 'PROMO_STALE');
  });
  await check('wholesale: price = smallest tier; discount pending', async () => {
    await db.collection('wholesale_products').doc('w1').set({ sellerId: OWNER, title: 'Un', status: 'active', publishedAt: TS.now(),
      priceTiers: [{ minQty: 1, price: 50000 }, { minQty: 10, price: 45000 }], priceTracked: 50000, priceSince: TS.fromMillis(Date.now() - 10 * DAY) });
    const d = await wsW('w1', (r) => r.update({ priceTiers: [{ minQty: 1, price: 40000 }], promoRequest: promoReq({ oldPrice: 50000 }) }));
    assert.strictEqual(d.priceTracked, 40000);
    assert.strictEqual(d.promoState.status, 'pending');
    assert.strictEqual(d.promoState.percent, 20);
    assert.strictEqual(requestKeyOf(d.promoRequest), d.promoState.requestKey);
  });
  await check('wholesale stock → stockLeft (sum), unknown pack → removed', async () => {
    await db.collection('wholesale_stock').doc('w1').set({ packs: { default: 3 } });
    await fns.onWholesaleStockBadge.run({ before: null, after: null }, { params: { productId: 'w1' } });
    assert.strictEqual((await get('wholesale_products', 'w1')).stockLeft, 3);
    // qadoqlar qo'shildi → p1/p2 qoldig'i yo'q → noma'lum.
    const d = await wsW('w1', (r) => r.update({ packs: [{ id: 'p1', label: '1 kg', priceTiers: [{ minQty: 1, price: 40000 }] }] }));
    assert.ok(!('stockLeft' in d));
  });
  await check('wholesale created active (auto-approve) → firstActiveAt', async () => {
    const d = await wsW('w2', (r) => r.set({ sellerId: OWNER, title: 'Yog\'', status: 'active', priceTiers: [{ minQty: 1, price: 1000 }] }));
    assert.ok(d.firstActiveAt);
  });

  await check('backfill tool: dry-run writes nothing; apply only docs without priceTracked; rollback', async () => {
    const tool = require('../tools/backfill_price_since');
    await db.collection('tv_shop_items').doc('legacy1').set(item({ price: 777 }));
    const dry = await tool.run({ db, apply: false, log: () => {} });
    assert.strictEqual(dry.touched.length, 1);
    assert.ok(!('priceTracked' in (await get('tv_shop_items', 'legacy1'))));
    const s2before = (await get('tv_shop_items', 's2')).priceSince.toMillis();
    const res = await tool.run({ db, apply: true, log: () => {} });
    assert.deepStrictEqual(res.touched, [{ col: 'tv_shop_items', id: 'legacy1' }]);
    const l = await get('tv_shop_items', 'legacy1');
    assert.strictEqual(l.priceTracked, 777);
    assert.ok(l.priceSince);
    assert.strictEqual((await get('tv_shop_items', 's2')).priceSince.toMillis(), s2before);
    const f = require('path').join(require('os').tmpdir(), `pp_rb_${Date.now()}.json`);
    require('fs').writeFileSync(f, JSON.stringify(res.touched));
    await tool.rollback({ db, file: f });
    assert.ok(!('priceTracked' in (await get('tv_shop_items', 'legacy1'))));
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
