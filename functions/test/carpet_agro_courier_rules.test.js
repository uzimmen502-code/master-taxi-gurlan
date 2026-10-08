/**
 * `carpet_wash_orders` / `agro_pickup_orders` Firestore rules — kuryer
 * (capability) vazifalar ro'yxati.
 *
 * Muammo (2026-10-08, jonli ruleset 510ad81c'da emulatorda tasdiqlangan):
 * `role: 'user'` + tasdiqlangan courier capability'li kuryer kuryer panelida
 * gilam va sut vazifalarini ocholmaydi. Ekranlar to'g'ridan-to'g'ri ro'yxat
 * so'raydi:
 *   - `carpet_wash_courier_screen.dart`: `status == pickup_ready`,
 *     `status == return_ready` (`watchByStatus`) va «Faol» tabida
 *     `watchAll(limit: 50)`;
 *   - `agro_pickup_courier_screen.dart`: `status == accepted` va
 *     `status == pickup_in_delivery` (HAMMA kuryerlarniki).
 * Ikkala qoida faqat `isStaff()` yoki `customerPhone` egasiga o'qish beradi,
 * `courier` esa `isStaff()`da yo'q (D-SERVICE-4 / D-CLEAN-1, jonli
 * 2026-10-06 13:21 UTC dan) — hammasi RAD. Xato ekranda ko'rinmasdi:
 * StreamBuilder xatoni «vazifa yo'q» deb ko'rsatardi.
 *
 * Tuzatish qoida orqali EMAS: qoida maydonlarni kesa olmaydi — ro'yxat
 * ochilsa, har bir kuryer vazifani olmasdan HAMMA mijozning ismi, telefoni,
 * manzili va izohini olardi (40-qoida). Ro'yxat `courierListCarpetTasks` /
 * `courierListAgroTasks` callable'lari orqali
 * (`functions/test/carpet_agro_courier_tasks_cf.test.js`); kuryer olgan
 * vazifasining tafsilotini ham callable ('active') beradi, shuning uchun
 * hujjatni to'g'ridan-to'g'ri o'qish kerak emas va qoida O'ZGARMADI.
 *
 * Bu test o'sha qarorni qulflaydi: kimdir «tez tuzatish» uchun qoidani
 * kuryerga ochsa — yiqiladi.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/carpet_agro_courier_rules.test.js"
 * Jonli qoidaga qarshi: `RULES_FILE=<yuklab olingan fayl>` bilan.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE
  || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const DISPATCHER = '998901112244';
const COURIER = '998905556677';
const COURIER_ACC = 'accCOURIER0000000000A';
/** Eski `role: 'courier'` — capability'siz (D-CLEAN-1 dan keyin huquq yo'q). */
const LEGACY = '998906660000';
const CUSTOMER = '998909990000';
const STRANGER = '998904445566';

const CARPET = 'carpet_wash_orders';
const AGRO = 'agro_pickup_orders';

function carpet(over = {}) {
  return {
    customerId: CUSTOMER, customerPhone: CUSTOMER, customerName: 'Mijoz',
    pickupAddress: 'Gurlan, Navoiy ko\'chasi 7', carpetCount: 3, note: '2-qavat',
    priceMode: 'admin', finalPrice: 0, status: 'pickup_ready',
    pickupCourierId: '', returnCourierId: '', createdAt: new Date(),
    ...over,
  };
}
function agro(over = {}) {
  return {
    customerId: CUSTOMER, customerPhone: CUSTOMER, customerName: 'Mijoz', productType: 'milk',
    pickupAddress: 'Gurlan, Navoiy ko\'chasi 7', literCount: 20, note: 'ertalab',
    priceMode: 'admin', finalPrice: 0, status: 'accepted', createdAt: new Date(),
    ...over,
  };
}

async function main() {
  console.log(`rules: ${RULES_PATH}`);
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-carpet-agro-courier',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });

  const results = [];
  const record = (name, pass, detail) => {
    results.push({ name, pass, detail });
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  };
  async function check(name, fn) {
    try { await fn(); record(name, true); } catch (e) { record(name, false, e.message); }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
    await db.collection('users').doc(COURIER).set({ role: 'user', accountId: COURIER_ACC });
    await db.collection('provider_capabilities').doc(COURIER_ACC).set({
      identity: { accountId: COURIER_ACC, primaryUid: COURIER },
      courier: { active: true },
      status: { courier: 'approved' },
    });
    await db.collection('users').doc(LEGACY).set({ role: 'courier' });
    await db.collection('users').doc(CUSTOMER).set({ role: 'user' });
    await db.collection('users').doc(STRANGER).set({ role: 'user' });

    await db.collection(CARPET).doc('c_ready').set(carpet());
    await db.collection(CARPET).doc('c_return').set(carpet({ status: 'return_ready' }));
    await db.collection(CARPET).doc('c_mine').set(carpet({
      status: 'pickup_in_delivery', pickupCourierId: COURIER,
    }));
    await db.collection(AGRO).doc('a_ready').set(agro());
    await db.collection(AGRO).doc('a_mine').set(agro({
      status: 'pickup_in_delivery', pickupCourierId: COURIER,
    }));
  });

  const ctxFor = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: '+' + phone });
  const unauth = testEnv.unauthenticatedContext().firestore();
  const courier = ctxFor(COURIER).firestore();
  const legacy = ctxFor(LEGACY).firestore();
  const customer = ctxFor(CUSTOMER).firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const dispatcher = ctxFor(DISPATCHER).firestore();
  const adminDb = ctxFor(ADMIN).firestore();

  // Ekranlardagi AYNAN shu so'rovlar (repository `watchByStatus` / `watchAll`).
  const byStatus = (db, col, status) => db.collection(col)
    .where('status', '==', status).orderBy('createdAt', 'desc').limit(50).get();
  const all = (db, col) => db.collection(col).orderBy('createdAt', 'desc').limit(50).get();
  const screenQueries = [
    ['gilam `pickup_ready`', (db) => byStatus(db, CARPET, 'pickup_ready')],
    ['gilam `return_ready`', (db) => byStatus(db, CARPET, 'return_ready')],
    ['gilam «Faol» `watchAll`', (db) => all(db, CARPET)],
    ['sut `accepted`', (db) => byStatus(db, AGRO, 'accepted')],
    ['sut `pickup_in_delivery`', (db) => byStatus(db, AGRO, 'pickup_in_delivery')],
  ];

  // ── Ekran so'rovlari: capability kuryer — RAD (callable orqali) ───────
  for (const [label, q] of screenQueries) {
    await check(`capability kuryer: ${label} ro'yxati to'g'ridan-to'g'ri RAD (PII) — callable orqali`,
      () => assertFails(q(courier)));
  }
  await check('eski `role: courier` (capability\'siz) ham ro\'yxatni ololmaydi',
    () => assertFails(byStatus(legacy, CARPET, 'pickup_ready')));
  await check('oddiy foydalanuvchi ro\'yxatni ololmaydi',
    () => assertFails(byStatus(stranger, AGRO, 'accepted')));
  await check('autentifikatsiyasiz ro\'yxat yo\'q', () => assertFails(byStatus(unauth, CARPET, 'pickup_ready')));

  // So'rov shakli to'g'ri — gap faqat huquqda (staff uchun ishlaydi).
  for (const [label, q] of screenQueries) {
    await check(`dispatcher (staff): ${label} ro'yxatini oladi`, () => assertSucceeds(q(dispatcher)));
  }
  await check('admin gilam ro\'yxatini oladi (admin panel)', () => assertSucceeds(all(adminDb, CARPET)));
  await check('admin sut ro\'yxatini oladi (admin panel)', () => assertSucceeds(all(adminDb, AGRO)));

  // ── Bitta hujjat: kuryer to'g'ridan-to'g'ri o'qimaydi ─────────────────
  await check('kuryer olinmagan gilam vazifasini get qila olmaydi (telefon/manzil)',
    () => assertFails(courier.collection(CARPET).doc('c_ready').get()));
  await check('kuryer olinmagan sut vazifasini get qila olmaydi',
    () => assertFails(courier.collection(AGRO).doc('a_ready').get()));
  await check('kuryer O\'Z olgan vazifasini ham to\'g\'ridan-to\'g\'ri o\'qimaydi — tafsilot callable (\'active\')',
    () => assertFails(courier.collection(CARPET).doc('c_mine').get()));
  await check('kuryer `pickupCourierId == men` ro\'yxatini ololmaydi',
    () => assertFails(courier.collection(AGRO).where('pickupCourierId', '==', COURIER).get()));

  // ── Mijoz oqimi o'zgarmadi ───────────────────────────────────────────
  await check('mijoz o\'z gilam buyurtmasini o\'qiydi',
    () => assertSucceeds(customer.collection(CARPET).doc('c_ready').get()));
  await check('mijoz o\'z gilam buyurtmalari ro\'yxatini oladi (watchForCustomer)',
    () => assertSucceeds(customer.collection(CARPET).where('customerPhone', '==', CUSTOMER)
      .orderBy('createdAt', 'desc').limit(30).get()));
  await check('mijoz o\'z sut buyurtmalari ro\'yxatini oladi (watchForCustomer)',
    () => assertSucceeds(customer.collection(AGRO).where('customerPhone', '==', CUSTOMER)
      .orderBy('createdAt', 'desc').limit(30).get()));
  await check('begona foydalanuvchi mijoz buyurtmasini o\'qiy olmaydi',
    () => assertFails(stranger.collection(AGRO).doc('a_ready').get()));

  // ── Yozish: faqat callable ───────────────────────────────────────────
  await check('kuryer vazifani to\'g\'ridan-to\'g\'ri claim qila olmaydi (yozish yo\'q)',
    () => assertFails(courier.collection(CARPET).doc('c_ready').update({
      status: 'pickup_in_delivery', pickupCourierId: COURIER,
    })));
  await check('kuryer sut vazifasini to\'g\'ridan-to\'g\'ri yopa olmaydi',
    () => assertFails(courier.collection(AGRO).doc('a_mine').update({ status: 'picked_up' })));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} carpet/agro courier rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
