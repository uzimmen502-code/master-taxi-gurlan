/**
 * `tv_shop_items` (AVAGram витрина, Бизнес харитаси маҳсулотлари) — қоидаларни қаттиқлаштириш, 2026-10-24.
 *
 *   firebase emulators:exec --only firestore --project demo-tv-shop-rules \
 *     "node test/tv_shop_items_rules.test.js"
 *   (бошқа қоида матнини синаш: RULES_FILE=<йўл>)
 *
 * Икки гуруҳ:
 *   A. Ҳозирги иловаларнинг БАРЧА мавжуд оқимлари (яратиш, расм таҳрири, видео боғлаш, матн таҳрири,
 *      юмшоқ ўчириш, админ) — ишлаши ШАРТ (эски APK'лар синмасин).
 *   B. Суиистеъмоллар — ўтиб кетса, қоидада тешик бор.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, arrayUnion, arrayRemove, Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const ADMIN = '998901110000';
const SELLER = '998911000001';
const OTHER = '998911000002';
const BIZ_MINE = 'biz_mine';
const BIZ_OTHERS = 'biz_others';
const BIZ_ADMIN = 'biz_admin_owned';

/** Aynan `TvShopItem.toMap()` shakli (lib/features/tv_market/models/tv_shop.dart). */
function appItem(extra = {}) {
  return {
    ownerPhone: SELLER,
    ownerName: 'Ali',
    title: 'Non',
    price: 5000,
    photoUrl: 'https://x/a.jpg',
    photoUrls: ['https://x/a.jpg'],
    kind: 'product',
    districtId: 'gurlan',
    districtLabel: '',
    description: 'Issiq non',
    clipIds: [],
    viewCount: 0,
    socialConsent: false,
    status: 'active',
    createdAt: serverTimestamp(),
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-tv-shop-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();
  const seed = (fn) => testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

  await testEnv.clearFirestore();
  await seed(async (db) => {
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${SELLER}`).set({ role: 'user' });
    await db.doc(`users/${OTHER}`).set({ role: 'user' });
    await db.doc(`businesses/${BIZ_MINE}`).set({ ownerId: SELLER, name: 'Mening', category: 'retail' });
    await db.doc(`businesses/${BIZ_OTHERS}`).set({ ownerId: OTHER, name: 'Begona', category: 'retail' });
    await db.doc(`businesses/${BIZ_ADMIN}`).set({ ownerId: 'admin', name: 'Egasiz', category: 'retail' });
  });
  const reset = async (id, data) => seed((db) => db.doc(`tv_shop_items/${id}`).set({ ...appItem(), createdAt: Timestamp.now(), ...data }));

  // ───────── A. Mavjud oqimlar ishlaydi ─────────
  await check('A1 oddiy vitrina yaratish (AVAGram nashri): ilovaning aniq shakli o\'tadi; pending ham', async () => {
    await assertSucceeds(as(SELLER).collection('tv_shop_items').add(appItem()));
    await assertSucceeds(as(SELLER).collection('tv_shop_items').add(appItem({ status: 'pending', kind: 'service' })));
  });

  await check('A2 Biznes mahsuloti: o\'z ob\'ektiga businessId bilan, 7 ta rasm bilan o\'tadi', async () => {
    const photos = Array.from({ length: 7 }, (_, i) => `https://x/${i}.jpg`);
    await assertSucceeds(as(SELLER).collection('tv_shop_items').add(appItem({ businessId: BIZ_MINE, photoUrls: photos })));
  });

  await check('A3 egasi tahrirlaydi: matn/narx/tur, rasmlar (<=7), video biriktirish/olib tashlash', async () => {
    await reset('t1', {});
    const ref = as(SELLER).doc('tv_shop_items/t1');
    await assertSucceeds(ref.update({ title: 'Yangi', price: 0, description: '', kind: 'service' }));
    await assertSucceeds(ref.update({ photoUrl: 'https://x/n.jpg', photoUrls: ['https://x/n.jpg', 'https://x/m.jpg'] }));
    await assertSucceeds(ref.update({ clipIds: arrayUnion('clip1') }));
    await assertSucceeds(ref.update({ clipIds: arrayRemove('clip1') }));
  });

  await check('A4 egasi yumshoq o\'chiradi (status deleted) va qattiq o\'chiradi', async () => {
    await reset('t2', {});
    await assertSucceeds(as(SELLER).doc('tv_shop_items/t2').update({ status: 'deleted' }));
    await reset('t3', {});
    await assertSucceeds(as(SELLER).doc('tv_shop_items/t3').delete());
  });

  await check('A5 admin: istalgan hujjatni tahrirlaydi (bloklash, tiklash, narx), o\'chiradi; hamma o\'qiydi (loginsiz ham)', async () => {
    await reset('t4', { businessId: BIZ_MINE });
    await assertSucceeds(as(ADMIN).doc('tv_shop_items/t4').update({ status: 'blocked' }));
    await assertSucceeds(as(ADMIN).doc('tv_shop_items/t4').update({ status: 'active', boostUntil: Timestamp.fromMillis(Date.now() + 86400000) }));
    await assertSucceeds(anon().doc('tv_shop_items/t4').get());
    await assertSucceeds(as(ADMIN).doc('tv_shop_items/t4').delete());
  });

  await check('A6 businessId yo\'q eski hujjat (businessId maydoni umuman yo\'q) tahrirlanadi', async () => {
    await seed((db) => db.doc('tv_shop_items/old1').set({ ownerPhone: SELLER, title: 'Eski', price: 100, status: 'active', kind: 'product' }));
    await assertSucceeds(as(SELLER).doc('tv_shop_items/old1').update({ title: 'Eski yangilandi' }));
  });

  // ───────── B. Suiiste'mollar rad etiladi ─────────
  const createFails = async (name, extra) =>
    check(`B create: ${name}`, async () => assertFails(as(SELLER).collection('tv_shop_items').add(appItem(extra))));

  await createFails('boostUntil ni o\'zi qo\'yadi (reyting aldovi)', { boostUntil: Timestamp.fromMillis(Date.now() + 86400000 * 30) });
  await createFails('socialPostedAt ni o\'zi qo\'yadi', { socialPostedAt: Timestamp.now() });
  await createFails('viewCount 5000', { viewCount: 5000 });
  await createFails('status blocked', { status: 'blocked' });
  await createFails('status deleted', { status: 'deleted' });
  await createFails('noma\'lum tur', { kind: 'weapon' });
  await createFails('tur news (vitrina emas)', { kind: 'news' });
  await createFails('boshqa klip ID larini oldindan yozadi', { clipIds: ['someone_elses_clip'] });
  await createFails('8 ta rasm', { photoUrls: Array.from({ length: 8 }, (_, i) => `https://x/${i}.jpg`) });
  await createFails('manfiy narx', { price: -1 });
  await createFails('kasr narx (pul butun)', { price: 12.5 });
  await createFails('narx matn', { price: '5000' });
  await createFails('juda katta narx', { price: 1000000000 });
  await createFails('sarlavha 201 belgi', { title: 'x'.repeat(201) });
  await createFails('tavsif 2001 belgi', { description: 'x'.repeat(2001) });
  await createFails('begona obyektga businessId', { businessId: BIZ_OTHERS });
  await createFails('mavjud bo\'lmagan obyektga businessId', { businessId: 'yoq_obyekt' });
  await createFails('egasiz (admin) obyektga businessId', { businessId: BIZ_ADMIN });
  await createFails('bo\'sh businessId', { businessId: '' });
  await createFails('businessId matn emas', { businessId: 123 });

  await check('B create: boshqa odam nomidan (ownerPhone begona) yaratib bo\'lmaydi; loginsiz ham', async () => {
    await assertFails(as(SELLER).collection('tv_shop_items').add(appItem({ ownerPhone: OTHER })));
    await assertFails(anon().collection('tv_shop_items').add(appItem()));
  });

  const updateFails = async (name, id, seedExtra, patch, who = SELLER) =>
    check(`B update: ${name}`, async () => {
      await reset(id, seedExtra);
      await assertFails(as(who).doc(`tv_shop_items/${id}`).update(patch));
    });

  await updateFails('boshqa eganing hujjati', 'u0', {}, { title: 'Hack' }, OTHER);
  await updateFails('boostUntil ni qo\'yish', 'u1', {}, { boostUntil: Timestamp.fromMillis(Date.now() + 86400000) });
  await updateFails('viewCount oshirish', 'u2', {}, { viewCount: 999 });
  await updateFails('ownerPhone o\'zgartirish', 'u3', {}, { ownerPhone: OTHER });
  await updateFails('admin bloklagan hujjatni o\'zi qayta faollashtirish', 'u4', { status: 'blocked' }, { status: 'active' });
  await updateFails('tasdiqlanmagan (pending) hujjatni o\'zi faollashtirish (moderatsiyani chetlab o\'tish)', 'u5', { status: 'pending' }, { status: 'active' });
  await updateFails('o\'chirilganni tiklash', 'u6', { status: 'deleted' }, { status: 'active' });
  await updateFails('o\'ziga noma\'lum status berish', 'u7', {}, { status: 'blocked' });
  await updateFails('businessId ni keyin biriktirish (begona obyektga)', 'u8', {}, { businessId: BIZ_OTHERS });
  await updateFails('businessId ni o\'z obyektiga ham keyin biriktirish (faqat yaratishda)', 'u9', {}, { businessId: BIZ_MINE });
  await updateFails('businessId ni boshqasiga o\'zgartirish', 'u10', { businessId: BIZ_MINE }, { businessId: BIZ_OTHERS });
  await updateFails('narxni manfiy qilish', 'u11', {}, { price: -5 });
  await updateFails('8 ta rasm', 'u12', {}, { photoUrls: Array.from({ length: 8 }, (_, i) => `https://x/${i}.jpg`) });
  await updateFails('51 ta klip', 'u13', {}, { clipIds: Array.from({ length: 51 }, (_, i) => `c${i}`) });
  await updateFails('tur weapon', 'u14', {}, { kind: 'weapon' });
  await updateFails('createdAt ni o\'zgartirish', 'u15', {}, { createdAt: Timestamp.fromMillis(1) });

  await check('B delete: boshqa eganing hujjatini o\'chirib bo\'lmaydi', async () => {
    await reset('d1', {});
    await assertFails(as(OTHER).doc('tv_shop_items/d1').delete());
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
