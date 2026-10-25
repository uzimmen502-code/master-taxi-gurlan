/**
 * Дўконнинг доимий ҳаволаси ва QR — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-shop-links "node test/shop_links.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-shop-links';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const links = require('../shop_links');

const db = admin.firestore();
const OWNER = '998914200001';
const OTHER = '998914200002';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
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
/** `shopPage` (onRequest) — сохта req/res. */
async function renderPage(path, lang = 'uz') {
  let status = 0;
  let body = '';
  const headers = {};
  const [p, qs] = path.split('?');
  const query = Object.fromEntries(new URLSearchParams(qs || ''));
  const req = { path: p, query, get: (h) => (h.toLowerCase() === 'accept-language' ? lang : '') };
  const res = {
    set: (k, v) => { headers[k] = v; return res; },
    status: (s) => { status = s; return res; },
    send: (b) => { body = String(b); return res; },
  };
  await fns.shopPage(req, res);
  return { status, body, headers };
}

async function main() {
  await clearEmulator();
  const T = admin.firestore.Timestamp;
  await db.collection('tv_shops').doc(OWNER).set({ name: 'Sidabilla', ownerPhone: OWNER });
  await db.collection('businesses').doc('m1').set({ ownerId: OWNER, name: 'Sidabilla — Kiyim', status: 'active' });
  await db.collection('businesses').doc('f1').set({ ownerId: OWNER, name: 'Kiyim (Urganch)', branchOf: 'm1', status: 'active' });
  await db.collection('businesses').doc('x1').set({ ownerId: OTHER, name: 'Begona', status: 'active' });
  const items = db.collection('tv_shop_items');
  await items.doc('i_own').set({ ownerPhone: OWNER, title: 'Non <b>issiq</b>', price: 5000, photoUrls: ['https://x/n.jpg'], status: 'active', createdAt: T.fromMillis(3) });
  await items.doc('i_k').set({ ownerPhone: OWNER, title: 'Ko\'ylak', price: 90000, photoUrls: ['https://x/k.jpg'], status: 'active', businessId: 'm1', createdAt: T.fromMillis(2) });
  await items.doc('i_kb').set({ ownerPhone: OWNER, title: 'Shim', price: 70000, status: 'blocked', businessId: 'm1', createdAt: T.fromMillis(1) });

  await check('P1 publicId: 10 belgi, telefon emas, adashtiradigan belgilarsiz; tekshiruv', () => {
    const seen = new Set();
    for (let i = 0; i < 200; i += 1) {
      const id = links.newPublicId();
      assert.ok(links.isPublicId(id), id);
      assert.ok(!/[0O1lI]/.test(id), id);
      seen.add(id);
    }
    assert.ok(seen.size > 195, 'takrorlanmaydi');
    for (const bad of ['', 'abc', '998914200001', 'abcdefghij/', 'abcdefghijk', null]) assert.strictEqual(links.isPublicId(bad), false, String(bad));
  });

  await check('P2 sahifa HTML: foydalanuvchi matni ekranlanadi (XSS yo\'q), OG teglari, telefon yo\'q; ru tili; topilmadi — noindex', () => {
    const html = links.buildShopPageHtml({
      shopName: '<script>alert(1)</script>', directionName: 'Kiyim', items: [{ title: 'Non <b>', price: 5000, photoUrl: 'javascript:alert(1)' }],
      pageUrl: 'https://master-taxi-gurlan.web.app/s/AbCdEfGh23', webUrl: 'https://master-taxi-gurlan.web.app/?shop=AbCdEfGh23', appUrl: 'https://play.google.com/x', altUrl: '',
    });
    assert.ok(!html.includes('<script>alert'), 'skript kiritilmaydi');
    assert.ok(html.includes('&lt;script&gt;'));
    assert.ok(!html.includes('javascript:'), 'xavfli sxema kesiladi');
    assert.ok(html.includes('og:title') && html.includes('?shop=AbCdEfGh23'));
    assert.ok(html.includes('5 000 сўм'));
    assert.ok(links.buildShopPageHtml({ shopName: 'S', items: [], webUrl: 'https://x/?shop=a', lang: 'ru' }).includes('Открыть магазин'));
    assert.ok(links.buildShopNotFoundHtml({}).includes('noindex'));
    assert.strictEqual(links.langOf('ru-RU,ru;q=0.9'), 'ru');
    assert.strictEqual(links.langOf('uz,en'), 'uz');
  });

  let shopId;
  let bizId;
  let branchId;
  await check('L1 getMyShopLink: loginsiz rad; o\'z do\'koni — havola beriladi, takror — o\'sha (o\'zgarmaydi)', async () => {
    await assert.rejects(call('getMyShopLink', {}, null));
    const r = await call('getMyShopLink', {}, OWNER);
    assert.ok(links.isPublicId(r.publicId));
    assert.strictEqual(r.url, `https://master-taxi-gurlan.web.app/s/${r.publicId}`);
    assert.ok(!r.url.includes(OWNER), 'havolada telefon yo\'q');
    shopId = r.publicId;
    assert.strictEqual((await call('getMyShopLink', {}, OWNER)).publicId, shopId);
    assert.strictEqual((await db.collection('tv_shops').doc(OWNER).get()).data().name, 'Sidabilla', 'nom tegilmagan');
  });

  await check('L2 yo\'nalish havolasi: o\'ziniki — beriladi; begona/yo\'q — BUSINESS_NOT_FOUND; filialga ham', async () => {
    bizId = (await call('getMyShopLink', { businessId: 'm1' }, OWNER)).publicId;
    branchId = (await call('getMyShopLink', { businessId: 'f1' }, OWNER)).publicId;
    assert.ok(links.isPublicId(bizId) && bizId !== shopId && branchId !== bizId);
    await expectCode(call('getMyShopLink', { businessId: 'x1' }, OWNER), 'BUSINESS_NOT_FOUND');
    await expectCode(call('getMyShopLink', { businessId: 'yoq' }, OWNER), 'BUSINESS_NOT_FOUND');
  });

  await check('L3 resolveShopLink (loginsiz): do\'kon -> egasi; yo\'nalish -> egasi+yo\'nalish; filial -> otasi; noma\'lum/axlat — mavjud emas', async () => {
    assert.deepStrictEqual(await call('resolveShopLink', { publicId: shopId }), { ok: true, available: true, ownerPhone: OWNER, businessId: '' });
    assert.deepStrictEqual(await call('resolveShopLink', { publicId: bizId }), { ok: true, available: true, ownerPhone: OWNER, businessId: 'm1' });
    assert.strictEqual((await call('resolveShopLink', { publicId: branchId })).businessId, 'm1');
    assert.deepStrictEqual(await call('resolveShopLink', { publicId: 'ZZZZZZZZZZ' }), { ok: true, available: false });
    assert.strictEqual((await call('resolveShopLink', { publicId: '../../x' })).available, false);
  });

  await check('L4 nom o\'zgarsa ham havola ishlaydi (ID bo\'yicha)', async () => {
    await db.collection('tv_shops').doc(OWNER).update({ name: 'Sidabilla Market' });
    const p = await renderPage(`/s/${shopId}`);
    assert.ok(p.body.includes('Sidabilla Market'));
  });

  await check('L5 /s/<id> sahifa: do\'kon nomi, faol mahsulotlar (ekranlangan), yo\'nalish — faqat uning mahsulotlari; telefon yo\'q', async () => {
    const all = await renderPage(`/s/${shopId}`);
    assert.strictEqual(all.status, 200);
    assert.ok(all.body.includes('Non &lt;b&gt;issiq&lt;/b&gt;') && all.body.includes('Ko&#39;ylak'));
    assert.ok(!all.body.includes('Shim'), 'bloklangan mahsulot yo\'q');
    assert.ok(!all.body.includes(OWNER) && !all.body.includes(OWNER.slice(3)), 'telefon yo\'q');
    assert.ok(/s-maxage=300/.test(all.headers['Cache-Control']));
    const dir = await renderPage(`/s/${bizId}`);
    assert.ok(dir.body.includes('Sidabilla — Kiyim') && dir.body.includes('Ko&#39;ylak'));
    assert.ok(!dir.body.includes('Non &lt;b&gt;'), 'boshqa yo\'nalish mahsuloti yo\'q');
    assert.ok(all.body.includes(`?shop=${shopId}&amp;src=link`), 'manba: havola');
    assert.ok((await renderPage(`/s/${shopId}?src=qr`)).body.includes(`?shop=${shopId}&amp;src=qr`), 'manba: QR');
    assert.ok((await renderPage(`/s/${shopId}?src=<x>`)).body.includes('src=link'), 'notanish manba -> link');
    const nf = await renderPage('/s/ZZZZZZZZZZ');
    assert.ok(nf.body.includes('noindex') && nf.body.includes('Дўкон топилмади'));
  });

  await check('L6 bloklangan do\'kon/yo\'nalish: havola ochilmaydi, yangi havola berilmaydi; blok olinsa yana ishlaydi', async () => {
    await db.collection('businesses').doc('m1').update({ status: 'blocked' });
    assert.strictEqual((await call('resolveShopLink', { publicId: bizId })).available, false);
    assert.ok((await renderPage(`/s/${bizId}`)).body.includes('noindex'));
    await expectCode(call('getMyShopLink', { businessId: 'm1' }, OWNER), 'BUSINESS_BLOCKED');
    await db.collection('tv_shops').doc(OWNER).update({ status: 'blocked' });
    assert.strictEqual((await call('resolveShopLink', { publicId: shopId })).available, false);
    await expectCode(call('getMyShopLink', {}, OWNER), 'SHOP_BLOCKED');
    await db.collection('tv_shops').doc(OWNER).update({ status: 'active' });
    await db.collection('businesses').doc('m1').update({ status: 'active' });
    assert.strictEqual((await call('resolveShopLink', { publicId: bizId })).available, true);
  });

  await check('L7 faqat yo\'nalishlari bor (tv_shops yo\'q) egaga ham o\'z do\'koni havolasi beriladi', async () => {
    await db.collection('businesses').doc('o1').set({ ownerId: OTHER, name: 'Faqat yo\'nalish', status: 'active' });
    const r = await call('getMyShopLink', {}, OTHER);
    const d = (await db.collection('tv_shops').doc(OTHER).get()).data();
    assert.deepStrictEqual([d.publicId, d.ownerPhone, d.name], [r.publicId, OTHER, '']);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
