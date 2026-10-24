/**
 * `wholesale_sellers` - rad etilgan sotuvchining QAYTA YUBORISHI
 * (firestore.rules -> `wholesaleSellerResubmitOk()`), 2026-10-24.
 *
 * NEGA: rad etilgan sotuvchi ilovada faqat sababni ko'rardi, chiqish yo'li yo'q edi.
 * Endi ma'lumotini tuzatib `rejected -> pending` qila oladi. Muhim: u ZINHOR
 * o'zini `approved` qila olmasligi va adminning `adminNote/approvedAt/approvedBy`
 * maydonlariga tegmasligi kerak.
 *
 *   firebase emulators:exec --only firestore --project demo-wholesale-sellers \
 *     "node functions/test/wholesale_sellers_rules.test.js"
 *
 * Boshqa qoidalar faylini tekshirish: RULES_FILE=<abs yo'l>.
 *
 * A - ilovaning aynan payload'i (WholesaleSeller.toFirestoreResubmit) o'tadi;
 * B - xavfsizlik: o'zini tasdiqlash, boshqa holat, begona kishi, buzuq ma'lumot - rad.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, deleteField } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const REJECTED = '998901000011';
const PENDING = '998901000012';
const APPROVED = '998901000013';
const OTHER = '998901000014';
const ADMIN = '998909990001';

/** Aynan `WholesaleSeller.toFirestoreResubmit()` shakli. */
function resubmitPayload(extra = {}) {
  return {
    companyName: 'Gurlan Savdo',
    ownerName: 'Ali',
    sellerType: 'wholesaler',
    approvalStatus: 'pending',
    updatedAt: serverTimestamp(),
    regionId: 'xorazm',
    districtId: 'gurlan',
    address: 'Markaz ko\'chasi 1',
    lat: 41.8,
    lng: 60.4,
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-wholesale-sellers',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push(p); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const rejected = ctx(REJECTED);
  const pending = ctx(PENDING);
  const approved = ctx(APPROVED);
  const other = ctx(OTHER);
  const admin = ctx(ADMIN);
  const doc = (db, id) => db.collection('wholesale_sellers').doc(id);

  const seed = async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore();
      await db.collection('users').doc(ADMIN).set({ role: 'admin' });
      const base = { companyName: 'Eski nom', ownerName: '', sellerType: 'wholesaler',
        regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1' };
      await db.collection('wholesale_sellers').doc(REJECTED).set({
        phone: REJECTED, ...base, approvalStatus: 'rejected', adminNote: 'Hujjat yetarli emas',
        approvedBy: ADMIN,
      });
      await db.collection('wholesale_sellers').doc(PENDING).set({ phone: PENDING, ...base, approvalStatus: 'pending' });
      await db.collection('wholesale_sellers').doc(APPROVED).set({ phone: APPROVED, ...base, approvalStatus: 'approved' });
    });
  };

  await seed();

  // A. Ilova oqimi
  await check('A1 rad etilgan sotuvchi: ilovaning aynan payload\'i - rejected->pending o\'tadi', () =>
    assertSucceeds(doc(rejected, REJECTED).update(resubmitPayload())));

  await seed();
  await check('A2 adminNote o\'zgarmay qoladi (admin qaroriga tegilmaydi)', async () => {
    await assertSucceeds(doc(rejected, REJECTED).update(resubmitPayload()));
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const s = await c.firestore().collection('wholesale_sellers').doc(REJECTED).get();
      if (s.data().adminNote !== 'Hujjat yetarli emas') throw new Error('adminNote o\'zgargan');
      if (s.data().approvalStatus !== 'pending') throw new Error('holat pending emas');
    });
  });

  await seed();
  await check('A3 admin qayta ko\'rib chiqadi (pending->approved) - o\'tadi', async () => {
    await assertSucceeds(doc(rejected, REJECTED).update(resubmitPayload()));
    await assertSucceeds(doc(admin, REJECTED).update({
      approvalStatus: 'approved', approvedAt: serverTimestamp(), approvedBy: ADMIN, adminNote: '',
    }));
  });

  // B. Xavfsizlik
  await seed();
  await check('B1 rad etilgan sotuvchi o\'zini APPROVED qila olmaydi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ approvalStatus: 'approved' }))));

  await check('B2 rad etilgan sotuvchi rejected holatini o\'zi qoldirib, boshqa maydon tegsa - faqat eski qoida', () =>
    // approvalStatus o'zgarmasa (rejected) bu eski egasi-tahriri qoidasi - ruxsat, lekin holatni o'zgartirmaydi
    assertSucceeds(doc(rejected, REJECTED).update({ companyName: 'Yangi nom', updatedAt: serverTimestamp() })));

  await check('B3 adminNote/approvedAt/approvedBy ga tegib bo\'lmaydi', async () => {
    await assertFails(doc(rejected, REJECTED).update(resubmitPayload({ adminNote: '' })));
    await assertFails(doc(rejected, REJECTED).update(resubmitPayload({ approvedBy: REJECTED })));
    await assertFails(doc(rejected, REJECTED).update(resubmitPayload({ approvedAt: serverTimestamp() })));
  });

  await check('B4 begona foydalanuvchi boshqaning arizasini qayta yubora olmaydi', () =>
    assertFails(doc(other, REJECTED).update(resubmitPayload())));

  await check('B5 pending sotuvchi: holat o\'zgarmaydi - faqat eski egasi-tahriri qoidasi (mavjud xulq)', async () => {
    await assertSucceeds(doc(pending, PENDING).update(resubmitPayload()));
    // lekin pending'dan approved'ga o'zi o'tolmaydi
    await assertFails(doc(pending, PENDING).update({ approvalStatus: 'approved' }));
  });

  await check('B6 tasdiqlangan sotuvchi approved->pending ga tushira olmaydi', () =>
    assertFails(doc(approved, APPROVED).update(resubmitPayload())));

  await check('B7 koordinatasiz qayta yuborish rad etiladi (rojxatdan o\'tish bilan bir xil talab)', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ lat: deleteField(), lng: deleteField() }))));

  await check('B8 O\'zbekiston tashqarisidagi koordinata rad etiladi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ lat: 55.7, lng: 37.6 }))));

  await check('B9 manzil 5 belgidan qisqa - rad etiladi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ address: 'abc' }))));

  await check('B10 tuman bo\'sh - rad etiladi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ districtId: '' }))));

  await check('B11 noto\'g\'ri sotuvchi turi - rad etiladi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ sellerType: 'hacker' }))));

  await check('B12 qo\'shimcha (ruxsatsiz) maydon - rad etiladi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ role: 'admin' }))));

  await check('B13 telefon almashtirib bo\'lmaydi', () =>
    assertFails(doc(rejected, REJECTED).update(resubmitPayload({ phone: OTHER }))));

  await check('B14 o\'chirib bo\'lmaydi', () => assertFails(doc(rejected, REJECTED).delete()));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
