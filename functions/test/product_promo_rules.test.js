/**
 * Карточка белгиси (эга 2026-11-19) — firestore.rules: сервер майдонлари қулф, сотувчи сўрови шакли.
 *
 *   firebase emulators:exec --only firestore --project demo-product-promo-rules "node test/product_promo_rules.test.js"
 *   (RULES_PATH билан бошқа файл, масалан stripped build, текширилади)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, deleteField, Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_PATH || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const DAY = 24 * 60 * 60 * 1000;
const OWNER = '998901000001';
const OTHER = '998901000003';
const ADMIN = '998909990001';

const shopItem = (extra = {}) => ({ ownerPhone: OWNER, title: 'Sut', description: 'd', price: 10000, photoUrls: ['p'], clipIds: [], kind: 'product', status: 'pending', viewCount: 0, ...extra });
const wsPayload = (extra = {}) => ({
  sellerId: OWNER, sellerCompanyName: 'G', title: 'Traktor', titleLower: 'traktor', description: 'Yangi traktor',
  priceTiers: [{ minQty: 1, price: 3800 }], unit: 'дона', imageUrls: ['https://e.test/a.jpg'], status: 'pending', views: 0,
  videoClipIds: [], searchTokens: ['traktor'], market: 'wholesale', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
});
const until = (days) => Timestamp.fromMillis(Date.now() + days * DAY);
const discount = (extra = {}) => ({ kind: 'discount', oldPrice: 12000, until: until(10), requestedAt: serverTimestamp(), ...extra });
const promo = (extra = {}) => ({ kind: 'promo', until: until(10), requestedAt: serverTimestamp(), ...extra });

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-product-promo-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  console.log(`rules: ${RULES_PATH}`);
  const results = [];
  const record = (n, p, d) => { results.push(p); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };
  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const owner = ctx(OWNER);
  const other = ctx(OTHER);
  const adminDb = ctx(ADMIN);

  const seed = async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore();
      await db.collection('users').doc(ADMIN).set({ role: 'admin' });
      await db.collection('wholesale_sellers').doc(OWNER).set({ phone: OWNER, companyName: 'G', approvalStatus: 'approved', regionId: 'xorazm', districtId: 'gurlan', address: 'M' });
      await db.collection('settings').doc('app').set({ wholesaleProductAutoApprove: false });
      await db.collection('tv_shop_items').doc('s1').set({ ...shopItem({ status: 'active' }), priceTracked: 10000, promo: { kind: 'promo' } });
      await db.collection('tv_shop_items').doc('s2').set({ ...shopItem({ status: 'active' }), promoRequest: { kind: 'promo', until: new Date(Date.now() + DAY), requestedAt: new Date(Date.now() - DAY) } });
      await db.collection('wholesale_products').doc('w1').set({ ...wsPayload({ status: 'active' }), createdAt: new Date('2026-10-01'), updatedAt: new Date('2026-10-01'), priceTracked: 3800 });
    });
  };
  await seed();
  const shop = (db) => db.collection('tv_shop_items');
  const ws = (db) => db.collection('wholesale_products');

  // ── tv_shop_items ──
  await check('T1 owner sets discount request — ok', () => assertSucceeds(shop(owner).doc('s1').update({ promoRequest: discount() })));
  await check('T2 owner sets promo (Aksiya) — ok', () => assertSucceeds(shop(owner).doc('s1').update({ promoRequest: promo() })));
  await check('T3 owner cancels (deleteField) — ok', () => assertSucceeds(shop(owner).doc('s1').update({ promoRequest: deleteField() })));
  await check('T4 until > 30 days — denied', () => assertFails(shop(owner).doc('s1').update({ promoRequest: promo({ until: until(31) }) })));
  await check('T5 until in the past — denied', () => assertFails(shop(owner).doc('s1').update({ promoRequest: promo({ until: until(-1) }) })));
  await check('T6 client requestedAt (not server time) — denied', () => assertFails(shop(owner).doc('s1').update({ promoRequest: promo({ requestedAt: Timestamp.now() }) })));
  await check('T7 free text key — denied', () => assertFails(shop(owner).doc('s1').update({ promoRequest: promo({ label: 'MEGA' }) })));
  await check('T8 discount without oldPrice / float oldPrice — denied', async () => {
    await assertFails(shop(owner).doc('s1').update({ promoRequest: { kind: 'discount', until: until(5), requestedAt: serverTimestamp() } }));
    await assertFails(shop(owner).doc('s1').update({ promoRequest: discount({ oldPrice: 12000.5 }) }));
  });
  await check('T9 promo with oldPrice — denied', () => assertFails(shop(owner).doc('s1').update({ promoRequest: promo({ oldPrice: 100 }) })));
  await check('T10 owner writes promo (approved badge) — denied', () => assertFails(shop(owner).doc('s1').update({ promo: { kind: 'discount', percent: 90 } })));
  for (const k of ['priceTracked', 'priceSince', 'priceHistory', 'promoState', 'firstActiveAt', 'stockLeft']) {
    await check(`T11 owner writes ${k} — denied`, () => assertFails(shop(owner).doc('s1').update({ [k]: 1 })));
  }
  await check('T12 other user sets request — denied', () => assertFails(shop(other).doc('s1').update({ promoRequest: promo() })));
  await check('T13 untouched old request (old requestedAt) — normal edit still ok', () => assertSucceeds(shop(owner).doc('s2').update({ title: 'Sut 2' })));
  await check('T14 create with server key — denied', () => assertFails(shop(owner).add(shopItem({ firstActiveAt: serverTimestamp() }))));
  await check('T15 create with promo request — ok; plain create ok', async () => {
    await assertSucceeds(shop(owner).add(shopItem({ promoRequest: promo() })));
    await assertSucceeds(shop(owner).add(shopItem()));
  });
  await check('T16 admin may write server fields (admin client) — ok', () => assertSucceeds(shop(adminDb).doc('s1').update({ stockLeft: 2 })));

  // ── wholesale_products ──
  await check('W1 owner sets discount request — ok', () => assertSucceeds(ws(owner).doc('w1').update({ promoRequest: discount() })));
  await check('W2 owner cancels — ok', () => assertSucceeds(ws(owner).doc('w1').update({ promoRequest: deleteField() })));
  await check('W3 until > 30 days — denied', () => assertFails(ws(owner).doc('w1').update({ promoRequest: promo({ until: until(31) }) })));
  await check('W4 owner writes promo / stockLeft / priceSince — denied', async () => {
    await assertFails(ws(owner).doc('w1').update({ promo: { kind: 'discount' } }));
    await assertFails(ws(owner).doc('w1').update({ stockLeft: 1 }));
    await assertFails(ws(owner).doc('w1').update({ priceSince: serverTimestamp() }));
  });
  await check('W5 create with promo request — ok; with server key — denied', async () => {
    await assertSucceeds(ws(owner).add(wsPayload({ promoRequest: promo() })));
    await assertFails(ws(owner).add(wsPayload({ promo: { kind: 'promo' } })));
  });
  await check('W6 existing content edit still ok', () => assertSucceeds(ws(owner).doc('w1').update({ title: 'Traktor 2', titleLower: 'traktor 2', status: 'pending', updatedAt: serverTimestamp() })));
  await check('W7 other user — denied', () => assertFails(ws(other).doc('w1').update({ promoRequest: promo() })));

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
