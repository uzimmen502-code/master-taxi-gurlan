/**
 * `wholesale_products.packs` va `wholesale_stock` qoidalari (2026-10-31).
 *
 *   RULES_FILE=<live+patch rules> firebase emulators:exec --only firestore \
 *     --project demo-wholesale-packs "node functions/test/wholesale_packs_rules.test.js"
 *
 * A — ishlashi SHART: qadoqli yaratish/tahrir, qadoqni o'chirish, qoldiqni
 *     hamma o'qiydi. B — teshik bo'lmasin: 6+ qadoq, `packs` ro'yxat emas,
 *     qoldiqqa klient (hatto egasi/admin) yozolmaydi.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, deleteField } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const SELLER = '998901000001';
const ADMIN = '998909990001';
const EXISTING = 'existing1';

const pack = (id, price) => ({ id, label: `${id} qop`, priceTiers: [{ minQty: 1, price }], unitWeightG: 1000 });

function createPayload(extra = {}) {
  return {
    sellerId: SELLER,
    sellerCompanyName: 'Gurlan Savdo',
    title: 'Guruch',
    titleLower: 'guruch',
    description: 'Lazer guruch',
    priceTiers: [{ minQty: 1, price: 15000 }],
    unit: 'дона',
    imageUrls: ['https://example.test/a.jpg'],
    status: 'pending',
    views: 0,
    videoClipIds: [],
    searchTokens: ['guruch'],
    market: 'wholesale',
    unitWeightG: 1000,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-wholesale-packs',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push(p); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const seller = ctx(SELLER);
  const admin = ctx(ADMIN);
  const anon = testEnv.unauthenticatedContext().firestore();
  const col = (db) => db.collection('wholesale_products');
  const stock = (db) => db.collection('wholesale_stock');

  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('wholesale_sellers').doc(SELLER).set({
      phone: SELLER, companyName: 'Gurlan Savdo', approvalStatus: 'approved',
      regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1',
    });
    await db.collection('settings').doc('app').set({ wholesaleProductAutoApprove: false });
    await db.collection('wholesale_products').doc(EXISTING).set({
      ...createPayload({ status: 'active', packs: [pack('p1', 15000)] }),
      createdAt: new Date('2026-10-01T10:00:00Z'),
      updatedAt: new Date('2026-10-01T10:00:00Z'),
    });
    await db.collection('wholesale_stock').doc(EXISTING).set({ packs: { p1: 10 }, version: 1 });
  });

  // ── A ───────────────────────────────────────────────────────────────
  await check('A1 qadoqsiz yaratish (eski shakl) — o\'tadi', () =>
    assertSucceeds(col(seller).add(createPayload())));
  await check('A2 5 ta qadoq bilan yaratish — o\'tadi', () =>
    assertSucceeds(col(seller).add(createPayload({
      packs: [pack('p1', 1), pack('p2', 2), pack('p3', 3), pack('p4', 4), pack('p5', 5)],
    }))));
  await check('A3 egasi qadoqlarni tahrirlaydi (pending) — o\'tadi', () =>
    assertSucceeds(col(seller).doc(EXISTING).update({
      packs: [pack('p1', 14000), pack('p2', 300000)],
      priceTiers: [{ minQty: 1, price: 14000 }],
      status: 'pending', updatedAt: serverTimestamp(),
    })));
  await check('A4 egasi qadoqlarni o\'chiradi (deleteField) — o\'tadi', () =>
    assertSucceeds(col(seller).doc(EXISTING).update({
      packs: deleteField(), status: 'pending', updatedAt: serverTimestamp(),
    })));
  await check('A5 qoldiqni kirmagan odam ham o\'qiydi', () =>
    assertSucceeds(stock(anon).doc(EXISTING).get()));

  // ── B ───────────────────────────────────────────────────────────────
  await check('B1 6 ta qadoq bilan yaratish — RAD', () =>
    assertFails(col(seller).add(createPayload({
      packs: [1, 2, 3, 4, 5, 6].map((i) => pack(`p${i}`, i)),
    }))));
  await check('B2 packs ro\'yxat emas — RAD', () =>
    assertFails(col(seller).add(createPayload({ packs: { p1: pack('p1', 1) } }))));
  await check('B3 tahrirda 6 ta qadoq — RAD', () =>
    assertFails(col(seller).doc(EXISTING).update({
      packs: [1, 2, 3, 4, 5, 6].map((i) => pack(`p${i}`, i)),
      status: 'pending', updatedAt: serverTimestamp(),
    })));
  await check('B4 egasi qoldiqqa yozolmaydi', () =>
    assertFails(stock(seller).doc(EXISTING).set({ packs: { p1: 999 } })));
  await check('B5 admin ham qoldiqqa klientdan yozolmaydi', () =>
    assertFails(stock(admin).doc(EXISTING).update({ packs: { p1: 0 } })));
  await check('B6 qoldiq tarixi o\'qilmaydi', () =>
    assertFails(stock(anon).doc(EXISTING).collection('history').doc('v1').get()));

  const passed = results.filter(Boolean).length;
  console.log(`\nwholesale_packs_rules: ${passed}/${results.length} passed`);
  await testEnv.cleanup();
  if (passed !== results.length) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
