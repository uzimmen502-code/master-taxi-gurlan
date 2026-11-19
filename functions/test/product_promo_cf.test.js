/**
 * Маҳсулот белгиси (эга 2026-11-19/20) — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-product-promo "node test/product_promo_cf.test.js"
 *
 * onShopItemPromoWrite, onWholesaleProductPromoWrite, onPlatformProductPromoWrite, onWholesaleStockBadge,
 * adminModeratePromo, adminSetProductDiscount, productPromoExpirySweep (runPromoExpirySweep), onShopItemModeration билан мослик.
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
const TRIG = { tv_shop_items: 'onShopItemPromoWrite', wholesale_products: 'onWholesaleProductPromoWrite', platform_products: 'onPlatformProductPromoWrite' };

async function writeAndRun(col, id, writeFn) {
  const ref = db.collection(col).doc(id);
  const before = await ref.get();
  await writeFn(ref);
  const after = await ref.get();
  await fns[TRIG[col]].run({ before, after }, { params: { docId: id }, timestamp: new Date().toISOString() });
  return (await ref.get()).data();
}
/** Сервер ёзувидан кейин триггер қайта ишласа — ҳеч нарса ёзилмаслиги (updateTime ўзгармайди). */
async function rerunIsNoop(col, id) {
  const ref = db.collection(col).doc(id);
  const s = await ref.get();
  await fns[TRIG[col]].run({ before: s, after: s }, { params: { docId: id } });
  return (await ref.get()).updateTime.toMillis() === s.updateTime.toMillis();
}
const shopW = (id, w) => writeAndRun('tv_shop_items', id, w);
const wsW = (id, w) => writeAndRun('wholesale_products', id, w);
const moderate = (data, who = ADMIN) => fns.adminModeratePromo.run(data, ctxOf(who));
const setDisc = (data, who = ADMIN) => fns.adminSetProductDiscount.run(data, ctxOf(who));
const held = (days) => ({ priceSince: TS.fromMillis(Date.now() - days * DAY) });
const item = (extra = {}) => ({ ownerPhone: OWNER, title: 'Qo\'y', price: 10000, priceTracked: 10000, ...held(10), status: 'active', moderatedAt: TS.now(), ...extra });
const discReq = (extra = {}) => ({ kind: 'discount', percent: 10, until: TS.fromMillis(Date.now() + 10 * DAY), requestedAt: TS.now(), ...extra });

async function approved(id, extra = {}) {
  await db.collection('tv_shop_items').doc(id).set(item(extra));
  await shopW(id, (r) => r.update({ promoRequest: discReq() }));
  await moderate({ collection: 'tv_shop_items', id, decision: 'approve' });
  return get('tv_shop_items', id);
}

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(OWNER).set({ role: 'user', appLang: 'uz_Latn' });

  await check('create → priceTracked + priceSince; first approval → firstActiveAt', async () => {
    const d = await shopW('s1', (r) => r.set({ ownerPhone: OWNER, title: 'x', price: 500, status: 'pending', moderatedAt: null }));
    assert.strictEqual(d.priceTracked, 500);
    assert.ok(!d.firstActiveAt);
    assert.ok((await shopW('s1', (r) => r.update({ status: 'active', moderatedAt: TS.now() }))).firstActiveAt);
  });

  await check('discount request (−10% of 10 000, held 10 d) → pending, price unchanged', async () => {
    await db.collection('tv_shop_items').doc('s2').set(item());
    const d = await shopW('s2', (r) => r.update({ promoRequest: discReq() }));
    assert.strictEqual(d.promoState.status, 'pending');
    assert.strictEqual(d.promoState.newPrice, 9000);
    assert.strictEqual(d.price, 10000);
  });
  await check('non-admin cannot moderate / set', async () => {
    await assert.rejects(moderate({ collection: 'tv_shop_items', id: 's2', decision: 'approve' }, OWNER));
    await assert.rejects(setDisc({ collection: 'platform_products', id: 'x', action: 'clear' }, OWNER));
  });
  await check('approve → REAL price 9000 (buyer pays), promo.basePrice 10000, audit, notified; trigger re-run no-op', async () => {
    const r = await moderate({ collection: 'tv_shop_items', id: 's2', decision: 'approve' });
    assert.strictEqual(r.status, 'active');
    const d = await get('tv_shop_items', 's2');
    assert.strictEqual(d.price, 9000);
    assert.strictEqual(d.priceTracked, 9000);
    assert.strictEqual(d.promo.basePrice, 10000);
    assert.strictEqual(d.promo.percent, 10);
    assert.strictEqual(d.promo.approvedBy, ADMIN);
    const a = (await db.collection('admin_audit').where('kind', '==', 'promo_moderation').get()).docs.map((x) => x.data());
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].newPrice, 9000);
    assert.ok((await db.collection('admin_news').where('targetUserId', '==', OWNER).get()).size >= 1);
    assert.ok(await rerunIsNoop('tv_shop_items', 's2'));
  });
  await check('server price write does NOT re-moderate (onShopItemModeration on same change)', async () => {
    const ref = db.collection('tv_shop_items').doc('s2');
    const before = await ref.get();
    await ref.update({ price: 9000 }); // o'zgarmagan qiymat — haqiqiy yozuvni taqlid
    const s = await ref.get();
    const b2 = { ...before.data(), price: 10000 };
    // Narx-faqat diff (10000 → 9000): moderatsiya rejasi yo'q.
    const { planShopItemWrite } = require('../market_moderation');
    assert.strictEqual(planShopItemWrite(b2, s.data(), Date.now()), null);
    assert.strictEqual(s.data().status, 'active');
  });
  await check('seller lowers price during promo (≠ base) → continues, % from base (floor)', async () => {
    const d = await shopW('s2', (r) => r.update({ price: 8550 }));
    assert.strictEqual(d.promo.percent, 14);
    assert.strictEqual(d.promo.sellerChanged, true);
    assert.strictEqual(d.price, 8550);
  });
  await check('expiry after seller change → seller price kept, badge dropped', async () => {
    await db.collection('tv_shop_items').doc('s2').update({ 'promo.until': TS.fromMillis(Date.now() - 1000) });
    await fns.productPromoExpirySweep.run({}, {});
    const d = await get('tv_shop_items', 's2');
    assert.strictEqual(d.price, 8550);
    assert.ok(!d.promo);
    assert.strictEqual(d.promoState.status, 'expired');
    assert.ok(await rerunIsNoop('tv_shop_items', 's2'), 'eski so\'rov qayta ko\'rilmaydi');
  });
  await check('expiry with server-set price → base restored (10 000); second sweep idempotent', async () => {
    await approved('s3');
    await db.collection('tv_shop_items').doc('s3').update({ 'promo.until': TS.fromMillis(Date.now() - 1000) });
    await fns.productPromoExpirySweep.run({}, {});
    const d = await get('tv_shop_items', 's3');
    assert.strictEqual(d.price, 10000);
    assert.strictEqual(d.priceTracked, 10000);
    assert.ok(!d.promo);
    const u1 = (await db.collection('tv_shop_items').doc('s3').get()).updateTime.toMillis();
    await fns.productPromoExpirySweep.run({}, {});
    assert.strictEqual((await db.collection('tv_shop_items').doc('s3').get()).updateTime.toMillis(), u1);
    assert.ok(await rerunIsNoop('tv_shop_items', 's3'));
  });
  await check('seller sets price == base during promo → cancelled', async () => {
    await approved('s4');
    const d = await shopW('s4', (r) => r.update({ price: 10000 }));
    assert.ok(!d.promo);
    assert.strictEqual(d.promoState.reason, 'PRICE_RESTORED');
    assert.strictEqual(d.price, 10000);
  });
  await check('seller cancels request during promo → base restored', async () => {
    await approved('s5');
    const d = await shopW('s5', (r) => r.update({ promoRequest: FV.delete() }));
    assert.strictEqual(d.price, 10000);
    assert.strictEqual(d.promoState.reason, 'CANCELLED');
  });
  await check('price held 6 days → rejected PRICE_NOT_7_DAYS', async () => {
    await db.collection('tv_shop_items').doc('s6').set(item(held(6)));
    const d = await shopW('s6', (r) => r.update({ promoRequest: discReq() }));
    assert.strictEqual(d.promoState.reason, 'PRICE_NOT_7_DAYS');
  });
  await check('Aksiya → active without moderation, price untouched; until > 30 d rejected', async () => {
    const d = await shopW('s6', (r) => r.update({ promoRequest: { kind: 'promo', until: TS.fromMillis(Date.now() + 5 * DAY), requestedAt: TS.now() } }));
    assert.strictEqual(d.promo.kind, 'promo');
    assert.strictEqual(d.price, 10000);
    const d2 = await shopW('s6', (r) => r.update({ promoRequest: { kind: 'promo', until: TS.fromMillis(Date.now() + 31 * DAY), requestedAt: TS.now() } }));
    assert.strictEqual(d2.promoState.reason, 'UNTIL_TOO_FAR');
  });
  await check('admin reject requires reason; stale → PROMO_STALE', async () => {
    await db.collection('tv_shop_items').doc('s7').set(item());
    await shopW('s7', (r) => r.update({ promoRequest: discReq() }));
    await expectCode(moderate({ collection: 'tv_shop_items', id: 's7', decision: 'reject' }), 'REASON_REQUIRED');
    await db.collection('tv_shop_items').doc('s7').update({ 'promoRequest.until': TS.fromMillis(Date.now() + 3 * DAY) });
    await expectCode(moderate({ collection: 'tv_shop_items', id: 's7', decision: 'approve' }), 'PROMO_STALE');
  });
  await check('approve when price changed before trigger → auto reject PRICE_CHANGED', async () => {
    await db.collection('tv_shop_items').doc('s8').set(item());
    await shopW('s8', (r) => r.update({ promoRequest: discReq() }));
    await db.collection('tv_shop_items').doc('s8').update({ price: 9500 });
    const r = await moderate({ collection: 'tv_shop_items', id: 's8', decision: 'approve' });
    assert.strictEqual(r.reason, 'PRICE_CHANGED');
    assert.strictEqual((await get('tv_shop_items', 's8')).price, 9500);
  });

  // ── wholesale ──
  const wsDoc = (extra = {}) => ({
    sellerId: OWNER, title: 'Un', status: 'active', publishedAt: TS.now(), priceTracked: 10000, ...held(10),
    priceTiers: [{ minQty: 1, price: 10000 }, { minQty: 10, price: 9999 }],
    packs: [{ id: 'p1', label: '1 kg', priceTiers: [{ minQty: 1, price: 10000 }, { minQty: 10, price: 9999 }] },
      { id: 'p2', label: '5 kg', priceTiers: [{ minQty: 1, price: 45001 }] }],
    ...extra,
  });
  await check('wholesale approve → every tier + pack tier discounted (floor); cancel → all restored', async () => {
    await db.collection('wholesale_products').doc('w1').set(wsDoc());
    await wsW('w1', (r) => r.update({ promoRequest: discReq() }));
    await moderate({ collection: 'wholesale_products', id: 'w1', decision: 'approve' });
    let d = await get('wholesale_products', 'w1');
    assert.deepStrictEqual(d.priceTiers, [{ minQty: 1, price: 9000 }, { minQty: 10, price: 8999 }]);
    assert.deepStrictEqual(d.packs[1].priceTiers, [{ minQty: 1, price: 40500 }]);
    assert.strictEqual(d.status, 'active');
    assert.ok(await rerunIsNoop('wholesale_products', 'w1'));
    d = await wsW('w1', (r) => r.update({ promoRequest: FV.delete() }));
    assert.deepStrictEqual(d.priceTiers, wsDoc().priceTiers);
    assert.deepStrictEqual(d.packs, wsDoc().packs);
  });
  await check('wholesale active: pack label edit → server pending; price-only edit → stays active', async () => {
    await db.collection('wholesale_products').doc('w2').set(wsDoc());
    let d = await wsW('w2', (r) => r.update({ packs: [{ ...wsDoc().packs[0], priceTiers: [{ minQty: 1, price: 11000 }] }, wsDoc().packs[1]] }));
    assert.strictEqual(d.status, 'active');
    d = await wsW('w2', (r) => r.update({ packs: [{ ...d.packs[0], label: '2 kg' }, d.packs[1]] }));
    assert.strictEqual(d.status, 'pending');
  });
  await check('wholesale stock → stockLeft; created active → firstActiveAt', async () => {
    await db.collection('wholesale_stock').doc('w3').set({ packs: { default: 3 } });
    await db.collection('wholesale_products').doc('w3').set({ sellerId: OWNER, title: 'Yog\'', status: 'active', priceTiers: [{ minQty: 1, price: 1000 }] });
    await fns.onWholesaleStockBadge.run({ before: null, after: null }, { params: { productId: 'w3' } });
    assert.strictEqual((await get('wholesale_products', 'w3')).stockLeft, 3);
    const d = await wsW('w4', (r) => r.set({ sellerId: OWNER, title: 'Yog\'', status: 'active', priceTiers: [{ minQty: 1, price: 1000 }] }));
    assert.ok(d.firstActiveAt);
  });

  // ── AVA (platform_products) — admin bevosita ──
  await check('AVA: adminSetProductDiscount set → price + priceTiers discounted, audit; clear → restored', async () => {
    await db.collection('platform_products').doc('pl1').set({ name: 'Un', price: 2000, priceTiers: [{ minQty: 1, price: 2100 }], priceTracked: 2000, ...held(8) });
    const r = await setDisc({ collection: 'platform_products', id: 'pl1', action: 'set', percent: 50, untilMs: Date.now() + 5 * DAY });
    assert.strictEqual(r.newPrice, 1000);
    let d = await get('platform_products', 'pl1');
    assert.strictEqual(d.price, 1000);
    assert.deepStrictEqual(d.priceTiers, [{ minQty: 1, price: 1050 }]);
    const a = (await db.collection('admin_audit').where('kind', '==', 'promo_admin_set').get()).docs.map((x) => x.data());
    assert.strictEqual(a.length, 1);
    assert.ok(await rerunIsNoop('platform_products', 'pl1'));
    await expectCode(setDisc({ collection: 'platform_products', id: 'pl1', action: 'set', percent: 10, untilMs: Date.now() + DAY }), 'PROMO_ACTIVE');
    await setDisc({ collection: 'platform_products', id: 'pl1', action: 'clear' });
    d = await get('platform_products', 'pl1');
    assert.strictEqual(d.price, 2000);
    assert.deepStrictEqual(d.priceTiers, [{ minQty: 1, price: 2100 }]);
  });
  await check('AVA: price held 6 d → PRICE_NOT_7_DAYS; until > 30 d → UNTIL_TOO_FAR; percent 91 → PERCENT_INVALID', async () => {
    await db.collection('platform_products').doc('pl2').set({ name: 'X', price: 2000, priceTracked: 2000, ...held(6) });
    await expectCode(setDisc({ collection: 'platform_products', id: 'pl2', action: 'set', percent: 10, untilMs: Date.now() + DAY }), 'PRICE_NOT_7_DAYS');
    await expectCode(setDisc({ collection: 'platform_products', id: 'pl2', action: 'set', percent: 10, untilMs: Date.now() + 31 * DAY }), 'UNTIL_TOO_FAR');
    await expectCode(setDisc({ collection: 'platform_products', id: 'pl2', action: 'set', percent: 91, untilMs: Date.now() + DAY }), 'PERCENT_INVALID');
  });

  await check('backfill tool: dry-run nothing; apply only docs without priceTracked (incl. platform); rollback', async () => {
    const tool = require('../tools/backfill_price_since');
    await db.collection('tv_shop_items').doc('legacy1').set({ ownerPhone: OWNER, title: 'L', price: 777, status: 'active' });
    await db.collection('platform_products').doc('legacy2').set({ name: 'L', price: 55 });
    const dry = await tool.run({ db, apply: false, log: () => {} });
    assert.ok(dry.touched.some((x) => x.id === 'legacy1') && dry.touched.some((x) => x.col === 'platform_products' && x.id === 'legacy2'));
    assert.ok(!('priceTracked' in (await get('tv_shop_items', 'legacy1'))));
    const res = await tool.run({ db, apply: true, log: () => {} });
    assert.strictEqual((await get('tv_shop_items', 'legacy1')).priceTracked, 777);
    assert.strictEqual((await get('platform_products', 'legacy2')).priceTracked, 55);
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
