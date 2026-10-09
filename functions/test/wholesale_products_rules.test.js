/**
 * `wholesale_products` — `createdAt` qoidasi (firestore.rules →
 * `wholesaleProductCreateOk()`), 2026-10-09.
 *
 * NEGA: admin ro'yxati `orderBy('createdAt')` bilan o'qiydi — maydonsiz
 * hujjat ro'yxatda umuman ko'rinmaydi, o'zboshimcha sana esa uni boshiga
 * yoki oxiriga surib qo'yadi. Ilova `FieldValue.serverTimestamp()`
 * yuboradi (modulning birinchi versiyasidan beri), qoida endi shuni
 * TALAB qiladi: `createdAt == request.time`. Keyin o'zgarmaydi.
 *
 *   firebase emulators:exec --only firestore --project demo-wholesale-rules \
 *     "node functions/test/wholesale_products_rules.test.js"
 *
 * Ikki guruh:
 *   A. Ilovaning mavjud oqimlari (yaratish, avto-tasdiq, Xitoy, tahrir,
 *      admin tasdig'i, ko'rishlar, video) — ishlashi SHART.
 *   B. Sana xavfsizligi — o'tib ketsa, qoidada teshik bor.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const SELLER = '998901000001';
const PENDING_SELLER = '998901000002';
const OTHER = '998901000003';
const ADMIN = '998909990001';
const EXISTING = 'existing1';

/** Aynan `WholesaleProduct.toFirestoreCreate()` shakli (lib/features/wholesale/models/wholesale_product.dart). */
function appCreatePayload(extra = {}) {
  return {
    sellerId: SELLER,
    sellerCompanyName: 'Gurlan Savdo',
    title: 'Traktor T-40',
    titleLower: 'traktor t-40',
    description: 'Yangi traktor, kafolat bilan',
    priceTiers: [{ minQty: 1, price: 3800 }],
    unit: 'дона',
    imageUrls: ['https://example.test/a.jpg'],
    status: 'pending',
    views: 0,
    videoClipIds: [],
    searchTokens: ['traktor', 't-40'],
    market: 'wholesale',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

function withoutKey(obj, key) {
  const copy = { ...obj };
  delete copy[key];
  return copy;
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-wholesale-products',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push(p); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  const ctx = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const seller = ctx(SELLER);
  const pendingSeller = ctx(PENDING_SELLER);
  const other = ctx(OTHER);
  const admin = ctx(ADMIN);
  const col = (db) => db.collection('wholesale_products');

  const seed = async ({ autoApprove = false } = {}) => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore();
      await db.collection('users').doc(ADMIN).set({ role: 'admin' });
      await db.collection('wholesale_sellers').doc(SELLER)
        .set({ phone: SELLER, companyName: 'Gurlan Savdo', approvalStatus: 'approved' });
      await db.collection('wholesale_sellers').doc(PENDING_SELLER)
        .set({ phone: PENDING_SELLER, companyName: 'Yangi', approvalStatus: 'pending' });
      await db.collection('settings').doc('app').set({ wholesaleProductAutoApprove: autoApprove });
      await db.collection('wholesale_products').doc(EXISTING).set({
        ...appCreatePayload({ status: 'active' }),
        createdAt: new Date('2026-09-28T15:22:03Z'),
        updatedAt: new Date('2026-09-28T15:22:03Z'),
      });
    });
  };

  await seed();

  // ── A. Ilova oqimlari — ishlashi SHART ─────────────────────────────────
  await check('A1 tasdiqlangan sotuvchi: ilovaning aynan payload\'i (serverTimestamp) — yaratiladi', () =>
    assertSucceeds(col(seller).add(appCreatePayload())));

  await check('A2 Xitoy bozori (valyuta + muddat) — yaratiladi', () =>
    assertSucceeds(col(seller).add(appCreatePayload({ market: 'china', currency: '$', deliveryDays: 20 }))));

  await check('A3 egasi kontentni tahrirlaydi (createdAt tegilmaydi) — o\'tadi', () =>
    assertSucceeds(col(seller).doc(EXISTING).update({
      title: 'Traktor T-40M', titleLower: 'traktor t-40m', status: 'pending', updatedAt: serverTimestamp(),
    })));

  await check('A4 admin tasdiqlaydi — o\'tadi', () =>
    assertSucceeds(col(admin).doc(EXISTING).update({
      status: 'active', publishedAt: serverTimestamp(), moderatedAt: serverTimestamp(), moderatedBy: ADMIN,
    })));

  await check('A5 boshqa foydalanuvchi ko\'rishlar sonini +1 qiladi — o\'tadi', () =>
    assertSucceeds(col(other).doc(EXISTING).update({ views: 1 })));

  await check('A6 egasi video bog\'laydi — o\'tadi', () =>
    assertSucceeds(col(seller).doc(EXISTING).update({ videoClipIds: ['clip1'], updatedAt: serverTimestamp() })));

  await seed({ autoApprove: true });
  await check('A7 avto-tasdiq yoqiq: darhol active (publishedAt/moderatedBy) — yaratiladi', () =>
    assertSucceeds(col(seller).add(appCreatePayload({
      status: 'active', publishedAt: serverTimestamp(), moderatedAt: serverTimestamp(), moderatedBy: 'auto',
    }))));
  await seed();

  // ── B. Sana xavfsizligi ────────────────────────────────────────────────
  await check('B1 createdAt YO\'Q — rad etiladi (admin ro\'yxatida ko\'rinmay qolardi)', () =>
    assertFails(col(seller).add(withoutKey(appCreatePayload(), 'createdAt'))));

  await check('B2 createdAt o\'tmishdagi sana (telefon vaqti) — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ createdAt: new Date('2020-01-01T00:00:00Z') }))));

  await check('B3 createdAt kelajakdagi sana (ro\'yxat boshiga chiqish) — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ createdAt: new Date('2030-01-01T00:00:00Z') }))));

  await check('B4 createdAt hozirgi telefon vaqti (new Date()) — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ createdAt: new Date() }))));

  await check('B5 createdAt satr — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ createdAt: '2026-10-09T00:00:00Z' }))));

  await check('B6 createdAt son (millisekund) — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ createdAt: Date.now() }))));

  await check('B7 createdAt null — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ createdAt: null }))));

  await check('B8 egasi createdAt\'ni o\'zgartira olmaydi (serverTimestamp bilan ham)', () =>
    assertFails(col(seller).doc(EXISTING).update({
      title: 'Traktor X', titleLower: 'traktor x', status: 'pending', createdAt: serverTimestamp(),
    })));

  await check('B9 egasi createdAt\'ni o\'tmishga sura olmaydi', () =>
    assertFails(col(seller).doc(EXISTING).update({ createdAt: new Date('2020-01-01T00:00:00Z') })));

  await check('B10 admin patch createdAt\'ni o\'zgartira olmaydi', () =>
    assertFails(col(admin).doc(EXISTING).update({ status: 'active', createdAt: serverTimestamp() })));

  await check('B11 video bog\'lash bilan createdAt o\'zgarmaydi', () =>
    assertFails(col(seller).doc(EXISTING).update({ videoClipIds: ['c2'], createdAt: serverTimestamp() })));

  await check('B12 ko\'rishlar +1 bilan createdAt o\'zgarmaydi', () =>
    assertFails(col(other).doc(EXISTING).update({ views: 1, createdAt: serverTimestamp() })));

  // Mavjud cheklovlar o'zgarmagan (regressiya).
  await check('B13 tasdiqlanmagan sotuvchi (to\'g\'ri sana bilan ham) — rad etiladi', () =>
    assertFails(col(pendingSeller).add(appCreatePayload({ sellerId: PENDING_SELLER }))));

  await check('B14 boshqaning sellerId\'si bilan yaratish — rad etiladi', () =>
    assertFails(col(other).add(appCreatePayload())));

  await check('B15 avto-tasdiq O\'CHIQ: active bilan yaratish — rad etiladi', () =>
    assertFails(col(seller).add(appCreatePayload({ status: 'active' }))));

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  await testEnv.cleanup();
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
