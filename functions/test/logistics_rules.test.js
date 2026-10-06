/**
 * AVA Logistics kolleksiyalari — Firestore rules (relay hujjati 7.7).
 * `logistics_orders`, `shipments` (+private), `custody_events`,
 * `route_plans`, `module_tariffs`, `logistics_audit`, `logistics_counters`
 * — HAMMASINI faqat server yozadi.
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/logistics_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const ADMIN = '998901112233';
const OWNER = '998902223344';
const K1 = '998903334455';    // tayinlangan ijrochi
const F1 = '998905556677';    // ikkinchi LEG ijrochisi
const STRANGER = '998904445566';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-logistics',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push({ n, p }); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    for (const u of [OWNER, K1, F1, STRANGER]) await db.collection('users').doc(u).set({ role: 'user' });
    await db.collection('logistics_orders').doc('o1').set({ ownerId: OWNER, status: 'ready', recipient: { phone: '998900000000' } });
    await db.collection('shipments').doc('s1').set({
      ownerId: OWNER, orderId: 'o1', status: 'in_transit', paymentStatus: 'escrow_funded',
      assignedProviderIds: [K1], priceSnapshot: { customerPrice: 240000 },
    });
    await db.collection('shipments').doc('s1').collection('private').doc('secrets').set({ qrSecret: 'abc' });
    await db.collection('shipments').doc('s1').collection('private').doc('internal').set({ platformShare: 48000 });
    await db.collection('custody_events').doc('e1').set({
      shipmentId: 's1', ownerId: OWNER, from: { kind: 'sender', id: OWNER }, to: { kind: 'provider', id: K1 }, kind: 'pickup',
    });
    await db.collection('custody_events').doc('e2').set({
      shipmentId: 's1', ownerId: OWNER, from: { kind: 'provider', id: K1 }, to: { kind: 'recipient', id: null }, kind: 'delivery',
    });
    await db.collection('route_plans').doc('s1').set({ currentVersion: 1 });
    await db.collection('route_plans').doc('s1').collection('versions').doc('1').set({ legs: [] });
    await db.collection('module_tariffs').doc('logistics_v1').set({ status: 'draft', internal: { platformMarginBps: 2000 } });
    await db.collection('module_tariffs').doc('logistics').set({ activeVersion: 1 });
    // Boshqa modul tarifi — eski umumiy qoida (authed o'qiydi, admin yozadi) saqlanadi.
    await db.collection('module_tariffs').doc('taxi').set({ formula: 'x' });
    await db.collection('logistics_audit').doc('a1').set({ kind: 'tariff_activate' });
    await db.collection('logistics_counters').doc('261007').set({ seq: 3 });
  });
  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p });
  const owner = ctxFor(OWNER).firestore();
  const k1 = ctxFor(K1).firestore();
  const f1 = ctxFor(F1).firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const adminDb = ctxFor(ADMIN).firestore();
  const unauth = testEnv.unauthenticatedContext().firestore();

  // logistics_orders
  await check('ORDER: egasi o\'qiydi (qabul qiluvchi telefoni shu yerda)', () => assertSucceeds(owner.collection('logistics_orders').doc('o1').get()));
  await check('ORDER: tayinlangan ijrochi ham O\'QIY OLMAYDI (telefon — 40-band)', () => assertFails(k1.collection('logistics_orders').doc('o1').get()));
  await check('ORDER: begona o\'qiy olmaydi; egasi yoza olmaydi', async () => {
    await assertFails(stranger.collection('logistics_orders').doc('o1').get());
    await assertFails(owner.collection('logistics_orders').doc('o1').update({ status: 'delivered' }));
    await assertFails(owner.collection('logistics_orders').doc('o2').set({ ownerId: OWNER }));
  });

  // shipments
  await check('SHIPMENT: egasi va tayinlangan ijrochi o\'qiydi', async () => {
    await assertSucceeds(owner.collection('shipments').doc('s1').get());
    await assertSucceeds(k1.collection('shipments').doc('s1').get());
  });
  await check('SHIPMENT: tayinlanmagan ijrochi va begona o\'qiy olmaydi', async () => {
    await assertFails(f1.collection('shipments').doc('s1').get());
    await assertFails(stranger.collection('shipments').doc('s1').get());
    await assertFails(unauth.collection('shipments').doc('s1').get());
  });
  await check('SHIPMENT: egasi statusni/narxni O\'ZI o\'zgartira olmaydi; ijrochi custody yoza olmaydi', async () => {
    await assertFails(owner.collection('shipments').doc('s1').update({ status: 'delivered' }));
    await assertFails(owner.collection('shipments').doc('s1').update({ 'priceSnapshot.customerPrice': 1 }));
    await assertFails(k1.collection('shipments').doc('s1').update({ currentCustodian: { kind: 'provider', id: K1 } }));
    await assertFails(k1.collection('shipments').doc('s1').update({ assignedProviderIds: [K1, F1] }));
  });
  await check('SHIPMENT private (sirlar, ichki narx): HECH KIM — egasi ham, admin ham', async () => {
    await assertFails(owner.collection('shipments').doc('s1').collection('private').doc('secrets').get());
    await assertFails(k1.collection('shipments').doc('s1').collection('private').doc('secrets').get());
    await assertFails(owner.collection('shipments').doc('s1').collection('private').doc('internal').get());
    await assertFails(adminDb.collection('shipments').doc('s1').collection('private').doc('secrets').get());
  });
  await check('SHIPMENT: admin o\'qiydi, klient SDK bilan yoza olmaydi', async () => {
    await assertSucceeds(adminDb.collection('shipments').doc('s1').get());
    await assertFails(adminDb.collection('shipments').doc('s1').update({ status: 'closed' }));
  });

  // custody_events
  await check('CUSTODY: egasi tarixni o\'qiydi; tomonlar o\'z hodisasini o\'qiydi', async () => {
    await assertSucceeds(owner.collection('custody_events').doc('e1').get());
    await assertSucceeds(k1.collection('custody_events').doc('e1').get());
    await assertSucceeds(k1.collection('custody_events').doc('e2').get());
  });
  await check('CUSTODY: begona o\'qiy olmaydi; hech kim yozmaydi/o\'chirmaydi (16-band)', async () => {
    await assertFails(f1.collection('custody_events').doc('e1').get());
    await assertFails(stranger.collection('custody_events').doc('e1').get());
    await assertFails(k1.collection('custody_events').doc('e3').set({ shipmentId: 's1', ownerId: OWNER, from: { id: K1 }, to: { id: F1 } }));
    await assertFails(owner.collection('custody_events').doc('e1').delete());
    await assertFails(adminDb.collection('custody_events').doc('e1').delete());
  });

  // route_plans / tariffs / audit / counters
  await check('ROUTE PLAN: faqat admin o\'qiydi, hech kim yozmaydi', async () => {
    await assertFails(owner.collection('route_plans').doc('s1').get());
    await assertFails(k1.collection('route_plans').doc('s1').collection('versions').doc('1').get());
    await assertSucceeds(adminDb.collection('route_plans').doc('s1').collection('versions').doc('1').get());
    await assertFails(adminDb.collection('route_plans').doc('s1').collection('versions').doc('2').set({ legs: [] }));
  });
  await check('TARIF: faqat admin o\'qiydi (mijoz narxni callable orqali oladi); hech kim yozmaydi', async () => {
    await assertFails(owner.collection('module_tariffs').doc('logistics_v1').get());
    await assertFails(owner.collection('module_tariffs').doc('logistics').get());
    await assertSucceeds(adminDb.collection('module_tariffs').doc('logistics_v1').get());
    await assertFails(adminDb.collection('module_tariffs').doc('logistics_v1').update({ status: 'active' }));
    await assertFails(adminDb.collection('module_tariffs').doc('logistics').update({ activeVersion: 2 }));
    await assertFails(adminDb.collection('module_tariffs').doc('logistics_v9').set({ status: 'draft' }));
  });
  await check('TARIF: boshqa modul tarifi — eski umumiy qoida o\'zgarmagan (authed o\'qiydi, admin yozadi)', async () => {
    await assertSucceeds(owner.collection('module_tariffs').doc('taxi').get());
    await assertFails(owner.collection('module_tariffs').doc('taxi').update({ formula: 'y' }));
    await assertSucceeds(adminDb.collection('module_tariffs').doc('taxi').update({ formula: 'y' }));
    await assertFails(unauth.collection('module_tariffs').doc('taxi').get());
  });

  // So'rovlar — ilova AYNAN shu filtrlar bilan yozilgan (logistics_repository.dart).
  await check('QUERY: egasi buyurtma/jo\'natma/custody ro\'yxatini ownerId filtri bilan oladi', async () => {
    await assertSucceeds(owner.collection('logistics_orders').where('ownerId', '==', OWNER).orderBy('createdAt', 'desc').limit(50).get());
    await assertSucceeds(owner.collection('shipments').where('ownerId', '==', OWNER).where('orderId', '==', 'o1').get());
    await assertSucceeds(owner.collection('custody_events').where('ownerId', '==', OWNER).where('shipmentId', '==', 's1').orderBy('timestamp').get());
  });
  await check('QUERY: ownerId filtrisiz so\'rov RAD (qoida isbotlanmaydi) — ilova bunday yozilmasligi kerak', async () => {
    await assertFails(owner.collection('shipments').where('orderId', '==', 'o1').get());
    await assertFails(owner.collection('custody_events').where('shipmentId', '==', 's1').get());
    await assertFails(owner.collection('logistics_orders').limit(10).get());
  });
  await check('QUERY: ijrochi faqat o\'ziga tayinlangan jo\'natmalarni so\'raydi (array-contains)', async () => {
    await assertSucceeds(k1.collection('shipments').where('assignedProviderIds', 'array-contains', K1).orderBy('updatedAt', 'desc').limit(50).get());
    await assertFails(k1.collection('shipments').where('assignedProviderIds', 'array-contains', F1).get());
    await assertFails(k1.collection('shipments').limit(10).get());
  });
  await check('QUERY: admin hamma jo\'natma va custody tarixini ko\'radi', async () => {
    await assertSucceeds(adminDb.collection('shipments').orderBy('updatedAt', 'desc').limit(100).get());
    await assertSucceeds(adminDb.collection('custody_events').where('shipmentId', '==', 's1').orderBy('timestamp').get());
    await assertSucceeds(adminDb.collection('module_tariffs').where('module', '==', 'logistics').get());
  });
  await check('AUDIT va COUNTER: audit faqat admin, counter hech kim', async () => {
    await assertFails(owner.collection('logistics_audit').doc('a1').get());
    await assertSucceeds(adminDb.collection('logistics_audit').doc('a1').get());
    await assertFails(adminDb.collection('logistics_counters').doc('261007').get());
    await assertFails(adminDb.collection('logistics_counters').doc('261007').update({ seq: 0 }));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.p);
  console.log(`\n${results.length - failed.length}/${results.length} logistics rules checks passed.`);
  if (failed.length) { console.log('FAILED:', failed.map((f) => f.n).join(', ')); process.exitCode = 1; }
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
