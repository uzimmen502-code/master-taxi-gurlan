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
const { serverTimestamp, deleteField } = require('firebase/firestore');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const SELLER = '998901000001';
const PENDING_SELLER = '998901000002';
const OTHER = '998901000003';
const NOADDR_SELLER = '998901000004'; // тасдиқланган, лекин манзилсиз (эски)
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
      // D-GEO-14 (2026-10-11): товар қўшиш учун сотувчида жўнатиш манзили шарт.
      await db.collection('wholesale_sellers').doc(SELLER)
        .set({ phone: SELLER, companyName: 'Gurlan Savdo', approvalStatus: 'approved',
          regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1' });
      await db.collection('wholesale_sellers').doc(NOADDR_SELLER)
        .set({ phone: NOADDR_SELLER, companyName: 'Eski Savdo', approvalStatus: 'approved' });
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

  // ── C. Yetkazish maydonlari (U1, 2026-10-09): vazn/o'lcham ixtiyoriy, shakli qat'iy ──
  await seed();
  await check('C1 unitWeightG + unitDims to\'g\'ri shaklda — yaratiladi', () =>
    assertSucceeds(col(seller).add(appCreatePayload({ unitWeightG: 1200, unitDims: { l: 30, w: 20, h: 15 } }))));
  await check('C2 faqat unitWeightG (o\'lchamsiz) — yaratiladi', () =>
    assertSucceeds(col(seller).add(appCreatePayload({ unitWeightG: 500 }))));
  await check('C3 unitWeightG 0 / manfiy / satr / 10 t dan ko\'p — rad', async () => {
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 0 })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: -5 })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: '1200' })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 10000001 })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 1.5 })));
  });
  await check('C4 unitDims: kalit yetishmasa / begona kalit / 0 / 1001 / satr — rad', async () => {
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 500, unitDims: { l: 30, w: 20 } })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 500, unitDims: { l: 30, w: 20, h: 15, kg: 1 } })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 500, unitDims: { l: 0, w: 20, h: 15 } })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 500, unitDims: { l: 1001, w: 20, h: 15 } })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 500, unitDims: { l: '30', w: 20, h: 15 } })));
    await assertFails(col(seller).add(appCreatePayload({ unitWeightG: 500, unitDims: [30, 20, 15] })));
  });
  await check('C5 egasi tahrirda vaznni qo\'shadi / o\'zgartiradi / o\'chiradi — o\'tadi; noto\'g\'ri — rad', async () => {
    await assertSucceeds(col(seller).doc(EXISTING).update({ unitWeightG: 900, unitDims: { l: 10, w: 10, h: 10 }, updatedAt: serverTimestamp() }));
    await assertSucceeds(col(seller).doc(EXISTING).update({ unitWeightG: 950, updatedAt: serverTimestamp() }));
    await assertFails(col(seller).doc(EXISTING).update({ unitWeightG: 0, updatedAt: serverTimestamp() }));
    await assertFails(col(seller).doc(EXISTING).update({ unitDims: { l: 10, w: 10 }, updatedAt: serverTimestamp() }));
    // Ilova o'chirishni FieldValue.delete() bilan yuboradi (toFirestoreOwnerUpdate).
    await assertSucceeds(col(seller).doc(EXISTING).update({ unitWeightG: deleteField(), unitDims: deleteField(), updatedAt: serverTimestamp() }));
  });
  await check('C6 begona (boshqa foydalanuvchi) vazn yoza olmaydi', () =>
    assertFails(col(other).doc(EXISTING).update({ unitWeightG: 1 })));

  // ── D. Sotuvchi jo'natish manzili (U1) ──────────────────────────────────
  const sellersCol = (db) => db.collection('wholesale_sellers');
  const NEW_SELLER = '998901000009';
  const newSellerDb = ctx(NEW_SELLER);
  const sellerCreate = (extra = {}) => ({
    phone: NEW_SELLER, companyName: 'Yangi Savdo', ownerName: '', sellerType: 'wholesaler',
    approvalStatus: 'pending', createdAt: serverTimestamp(), ...extra,
  });
  // D-GEO-14 (эга, 2026-10-11): манзил МАЖБУРИЙ — аввал бу ўтарди.
  await check('D1 manzilsiz ro\'yxatdan o\'tish — RAD (D-GEO-14)', async () => {
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate()));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ regionId: 'xorazm' })));
  });
  await seed();
  await check('D2 manzil bilan (region/district/address/lat/lng) — yaratiladi', () =>
    assertSucceeds(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({
      regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1', lat: 41.84, lng: 60.39,
    }))));
  await seed();
  // Эга, 2026-10-23: ЯНГИ сотувчида манзил матни (≥5) ва координата ҳам мажбурий (бизнес харитаси).
  await check('D2b yangi sotuvchi: koordinatasiz / manzilsiz-qisqa manzil / O\'zbekiston tashqarisi — RAD', async () => {
    const geo = { regionId: 'xorazm', districtId: 'gurlan' };
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, address: 'Markaz 1' })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, lat: 41.84, lng: 60.39 })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, address: 'abcd', lat: 41.84, lng: 60.39 })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, address: 'Markaz 1', lat: 10, lng: 60.39 })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, address: 'Markaz 1', lat: 41.84, lng: 100 })));
  });
  await check('D2c chegara: Ozbekiston qutisining chekka qiymatlari va 5 belgili manzil — o\'tadi', async () => {
    const geo = { regionId: 'xorazm', districtId: 'gurlan' };
    await assertSucceeds(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, address: 'abcde', lat: 36, lng: 55 })));
    await seed();
    await assertSucceeds(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ ...geo, address: 'abcde', lat: 46, lng: 74 })));
  });
  await seed();
  await check('D3 noto\'g\'ri manzil: lat satr / lat yolg\'iz / lat 95 / tuman viloyatsiz / manzil 301 — rad', async () => {
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ regionId: 'x', districtId: 'g', lat: '41', lng: 60 })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ regionId: 'x', districtId: 'g', lat: 41 })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ regionId: 'x', districtId: 'g', lat: 95, lng: 60 })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ districtId: 'g' })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ regionId: 'x', districtId: 'g', address: 'a'.repeat(301) })));
    await assertFails(sellersCol(newSellerDb).doc(NEW_SELLER).set(sellerCreate({ regionId: 'x', districtId: 'g', warehouse: 'A' })));
  });
  await check('D4 egasi keyin manzilini kiritadi/o\'zgartiradi — o\'tadi; approvalStatus bilan birga — rad; begona — rad', async () => {
    await assertSucceeds(sellersCol(seller).doc(SELLER).update({
      regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1', updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(sellersCol(seller).doc(SELLER).update({ lat: 41.84, lng: 60.39, updatedAt: serverTimestamp() }));
    // Seed'da sotuvchi allaqachon `approved` — o'zgarmagan qiymat affectedKeys'ga
    // kirmaydi, shuning uchun HAQIQIY o'zgarish bilan tekshiriladi.
    await assertFails(sellersCol(seller).doc(SELLER).update({ districtId: 'xiva', approvalStatus: 'rejected' }));
    await assertFails(sellersCol(pendingSeller).doc(PENDING_SELLER).update({ districtId: 'xiva', approvalStatus: 'approved' }));
    await assertFails(sellersCol(other).doc(SELLER).update({ districtId: 'xiva' }));
  });

  // ── E. D-GEO-14: манзил мажбурий, товар ҳудуди сервердан ─────────────────
  await seed();
  const noAddr = ctx(NOADDR_SELLER);
  await check('E1 manzilsiz (eski) sotuvchi tovar qo\'sha olmaydi', () =>
    assertFails(col(noAddr).add(appCreatePayload({ sellerId: NOADDR_SELLER, sellerCompanyName: 'Eski Savdo' }))));
  await check('E2 manzilsiz sotuvchi profilini tahrirlay oladi va manzil kiritadi', async () => {
    await assertSucceeds(sellersCol(noAddr).doc(NOADDR_SELLER).update({ companyName: 'Eski Savdo 2', updatedAt: serverTimestamp() }));
    await assertSucceeds(sellersCol(noAddr).doc(NOADDR_SELLER).update({
      regionId: 'xorazm', districtId: 'xiva', address: 'Bozor 3', updatedAt: serverTimestamp(),
    }));
  });
  await check('E3 kiritilgan manzilni bo\'shatib bo\'lmaydi', async () => {
    await assertFails(sellersCol(seller).doc(SELLER).update({ districtId: '', updatedAt: serverTimestamp() }));
    await assertFails(sellersCol(seller).doc(SELLER).update({ districtId: deleteField(), regionId: deleteField() }));
  });
  await check('E4 tovarga hudud (regionId/districtId) ni mijoz yoza olmaydi — faqat server', async () => {
    await assertFails(col(seller).add(appCreatePayload({ regionId: 'toshkent_shahri', districtId: 'chilonzor' })));
    await assertFails(col(seller).doc(EXISTING).update({ districtId: 'chilonzor', updatedAt: serverTimestamp() }));
  });

  // ── F. Расмлар сони: 1..7 (эга қарори, 2026-10-17; аввал 1..5) ────────────
  await seed();
  const imgs = (n) => Array.from({ length: n }, (_, i) => `https://example.test/${i}.jpg`);
  await check('F1 yaratish: 5 ta rasm (eski ilova) — o\'tadi (orqaga moslik)', () =>
    assertSucceeds(col(seller).add(appCreatePayload({ imageUrls: imgs(5) }))));
  await check('F2 yaratish: 7 ta rasm (chegara) — o\'tadi', () =>
    assertSucceeds(col(seller).add(appCreatePayload({ imageUrls: imgs(7) }))));
  await check('F3 yaratish: 8 ta rasm — rad', () =>
    assertFails(col(seller).add(appCreatePayload({ imageUrls: imgs(8) }))));
  await check('F4 yaratish: 0 ta rasm — rad', () =>
    assertFails(col(seller).add(appCreatePayload({ imageUrls: [] }))));
  await check('F5 tahrir: 7 taga oshirish — o\'tadi, 8 taga — rad', async () => {
    await assertSucceeds(col(seller).doc(EXISTING).update({ imageUrls: imgs(7), status: 'pending', updatedAt: serverTimestamp() }));
    await assertFails(col(seller).doc(EXISTING).update({ imageUrls: imgs(8), status: 'pending', updatedAt: serverTimestamp() }));
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  await testEnv.cleanup();
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
