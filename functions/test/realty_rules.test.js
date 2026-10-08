/**
 * `realty_listings` Firestore qoidalari — «Ko'chmas mulk klasteri»ning
 * PEYVOLLI.
 *
 * NEGA BU TEST BOR: bu bo'limda pul aynan qoida chegarasida ushlab
 * turiladi. Aniq koordinata va aloqa raqami yopiq
 * `realty_listings/{id}/private/detail` hujjatida; uni o'qish huquqini
 * axborot paketi beradi (`users/{uid}/realty_unlocked/{listingId}`).
 * Ya'ni ilovadagi hech qanday ekran emas, aynan `firestore.rules`
 * «to'laganmi yoki yo'qmi» degan savolga javob beradi. Qoida bitta
 * qatordan adashsa — paket sotishning ma'nosi qolmaydi va buni
 * ilovaga qarab sezib bo'lmaydi.
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida ishlaydi, hech
 * qanday real ma'lumotga tegmaydi (`ev_charging_rules.test.js`
 * shabloniga mos).
 *
 * Talab qilinadi: `firebase emulators:start --only firestore`
 * Ishlatish: npm run test:realty-rules
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

/** Egasi (uning `realtyOwnerKey` i OWNER_KEY). */
const OWNER = '998901112233';
/** Paketdan shu obyektni OCHGAN xaridor. */
const BUYER = '998904445566';
/** Hech nima to'lamagan foydalanuvchi. */
const STRANGER = '998907778899';
const ADMIN_PHONE = '998909998877';

const OWNER_KEY = 'ownerkey_abc123';
const LISTING = 'listing1';
const OTHER_LISTING = 'listing2';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-realty',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  function record(name, pass, detail) {
    results.push({ name, pass, detail });
    console.log(
      `${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`,
    );
  }
  async function check(name, fn) {
    try {
      await fn();
      record(name, true);
    } catch (e) {
      record(name, false, e.message);
    }
  }

  await testEnv.clearFirestore();

  const anon = testEnv.authenticatedContext('guestUid', {
    firebase: { sign_in_provider: 'anonymous' },
  });
  const owner = testEnv.authenticatedContext('uidOwner', {
    phone_number: '+' + OWNER,
  });
  const buyer = testEnv.authenticatedContext('uidBuyer', {
    phone_number: '+' + BUYER,
  });
  const stranger = testEnv.authenticatedContext('uidStranger', {
    phone_number: '+' + STRANGER,
  });
  const admin = testEnv.authenticatedContext('uidAdmin', {
    phone_number: '+' + ADMIN_PHONE,
  });
  const dbAnon = anon.firestore();
  const dbOwner = owner.firestore();
  const dbBuyer = buyer.firestore();
  const dbStranger = stranger.firestore();
  const dbAdmin = admin.firestore();

  // ─── Boshlang'ich holat: Admin SDK nima yozsa, shuni yozamiz ───
  // Hammasini qoidalardan o'tmasdan urug'lantiramiz: haqiqiy loyihada
  // bu yozuvlarni `submitRealtyListing` / `unlockRealtyListing` (Admin
  // SDK) yaratadi, client esa hech qachon.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN_PHONE).set({ role: 'admin' });
    await db.collection('users').doc(OWNER).set({
      phone: OWNER,
      realtyOwnerKey: OWNER_KEY,
    });
    await db.collection('users').doc(BUYER).set({
      phone: BUYER,
      realtyUnlocksLeft: 4,
    });
    await db.collection('users').doc(STRANGER).set({ phone: STRANGER });

    for (const id of [LISTING, OTHER_LISTING]) {
      await db.collection('realty_listings').doc(id).set({
        ownerKey: OWNER_KEY,
        ownerName: 'Ega',
        deal: 'sale',
        tier: 'plain',
        title: 'Uch xonali',
        text: 'Markazda',
        status: 'active',
        areaLat: 41.511,
        areaLng: 60.611,
      });
      await db.collection('realty_listings').doc(id)
        .collection('private').doc('detail').set({
          ownerId: OWNER,
          lat: 41.5,
          lng: 60.6,
          ownerPhone: OWNER,
        });
    }

    // Xaridor FAQAT bitta obyektni ochgan.
    await db.collection('users').doc(BUYER)
      .collection('realty_unlocked').doc(LISTING)
      .set({ listingId: LISTING, unlockedAt: new Date() });
  });

  // ─── OCHIQ hujjat: lentani mehmon ham ko'radi ───
  // Konsepsiya, 9-bo'lim: lenta hammaga, xarita va e'lon joylash —
  // ro'yxatdan o'tganlarga.
  await check('mehmon (anonim) lentani o\'qiydi', () =>
    assertSucceeds(dbAnon.collection('realty_listings').doc(LISTING).get()));
  await check('ro\'yxatdan o\'tgan foydalanuvchi lentani o\'qiydi', () =>
    assertSucceeds(
      dbStranger.collection('realty_listings').doc(LISTING).get()));

  // ─── PEYVOLL: yopiq hujjat ───
  await check('PEYVOLL: to\'lamagan foydalanuvchi aniq nuqtani o\'qiy OLMAYDI',
    () => assertFails(
      dbStranger.collection('realty_listings').doc(LISTING)
        .collection('private').doc('detail').get()));
  await check('PEYVOLL: mehmon ham o\'qiy OLMAYDI', () =>
    assertFails(
      dbAnon.collection('realty_listings').doc(LISTING)
        .collection('private').doc('detail').get()));
  await check('paketdan ochgan xaridor o\'qiydi', () =>
    assertSucceeds(
      dbBuyer.collection('realty_listings').doc(LISTING)
        .collection('private').doc('detail').get()));
  await check(
    'bitta obyekt uchun to\'lov BOSHQA obyektni ochmaydi',
    () => assertFails(
      dbBuyer.collection('realty_listings').doc(OTHER_LISTING)
        .collection('private').doc('detail').get()));
  await check('ega o\'z obyektini o\'qiydi (ownerKey bo\'yicha)', () =>
    assertSucceeds(
      dbOwner.collection('realty_listings').doc(LISTING)
        .collection('private').doc('detail').get()));
  await check('admin o\'qiydi', () =>
    assertSucceeds(
      dbAdmin.collection('realty_listings').doc(LISTING)
        .collection('private').doc('detail').get()));

  // ─── O'zini o'zi «ochib» qo'yish mumkin emas ───
  // `realty_unlocked` hujjati — to'lovning ISBOTI, shuning uchun uni
  // faqat `unlockRealtyListing` (Admin SDK) yaratadi.
  await check(
    'MUHIM: foydalanuvchi o\'ziga TEKINGA unlock yozib qo\'ya olmaydi',
    () => assertFails(
      dbStranger.collection('users').doc(STRANGER)
        .collection('realty_unlocked').doc(LISTING)
        .set({ listingId: LISTING, unlockedAt: new Date() })));
  await check('boshqa odamning unlock ro\'yxati o\'qilmaydi', () =>
    assertFails(
      dbStranger.collection('users').doc(BUYER)
        .collection('realty_unlocked').doc(LISTING).get()));
  await check('xaridor o\'z unlock ro\'yxatini o\'qiydi', () =>
    assertSucceeds(
      dbBuyer.collection('users').doc(BUYER)
        .collection('realty_unlocked').doc(LISTING).get()));

  // ─── Paket qoldig'i va ega kaliti — faqat server ───
  await check(
    'MUHIM: foydalanuvchi o\'ziga paket o\'rni yozib qo\'ya olmaydi',
    () => assertFails(
      dbStranger.collection('users').doc(STRANGER)
        .update({ realtyUnlocksLeft: 99 })));
  await check(
    'MUHIM: foydalanuvchi realtyOwnerKey ni o\'zgartira olmaydi '
    + '(boshqaning e\'lonini o\'ziniki qilib olish)',
    () => assertFails(
      dbStranger.collection('users').doc(STRANGER)
        .update({ realtyOwnerKey: OWNER_KEY })));
  await check('MUHIM: realtyPro ni o\'ziga yozib qo\'ya olmaydi', () =>
    assertFails(
      dbStranger.collection('users').doc(STRANGER).update({
        realtyPro: { planId: 'pro_150', objects: 150, expiresAt: new Date() },
      })));

  // ─── E'lonning OCHIQ hujjati ham client tomonidan yozilmaydi ───
  // Bepul limit, hudud tamg'asi va muddat serverda hisoblanadi
  // (`ev_charging_stations` bilan bir xil qoida).
  await check('client to\'g\'ridan-to\'g\'ri e\'lon YARATA olmaydi', () =>
    assertFails(
      dbStranger.collection('realty_listings').doc('fake').set({
        ownerKey: 'x', title: 'Yolg\'on', text: 'Matn', status: 'active',
      })));
  await check('ega ham o\'z e\'lonini to\'g\'ridan-to\'g\'ri tahrirlay olmaydi',
    () => assertFails(
      dbOwner.collection('realty_listings').doc(LISTING)
        .update({ priceText: '1 so\'m' })));
  await check('ega ham o\'z e\'lonini to\'g\'ridan-to\'g\'ri o\'chira olmaydi',
    () => assertFails(
      dbOwner.collection('realty_listings').doc(LISTING).delete()));
  await check('ega yopiq hujjatga YOZA olmaydi (faqat o\'qiydi)', () =>
    assertFails(
      dbOwner.collection('realty_listings').doc(LISTING)
        .collection('private').doc('detail')
        .update({ ownerPhone: STRANGER })));
  await check('admin e\'lonni tahrirlaydi (moderatsiya)', () =>
    assertSucceeds(
      dbAdmin.collection('realty_listings').doc(LISTING)
        .update({ status: 'blocked' })));

  // ─── Rieltor vositalari: o'z qulayligi, pul bilan bog'liq emas ───
  await check('ega o\'z «saqlangan uy»ini yozadi', () =>
    assertSucceeds(
      dbOwner.collection('users').doc(OWNER)
        .collection('realty_places').doc('p1')
        .set({ label: 'Navoiy 12', lat: 41.5, lng: 60.6 })));
  await check('boshqa odamning «saqlangan uy»lari yozilmaydi', () =>
    assertFails(
      dbStranger.collection('users').doc(OWNER)
        .collection('realty_places').doc('p2')
        .set({ label: 'Yolg\'on', lat: 41.5, lng: 60.6 })));
  await check('ega o\'z shablonini yozadi', () =>
    assertSucceeds(
      dbOwner.collection('users').doc(OWNER)
        .collection('realty_prefs').doc('template')
        .set({ text: 'Kompaniya standart matni' })));
  await check('boshqa odamning shabloni o\'qilmaydi', () =>
    assertFails(
      dbStranger.collection('users').doc(OWNER)
        .collection('realty_prefs').doc('template').get()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(
    `\n${results.length - failed.length}/${results.length} `
    + 'realty_listings rules checks passed.',
  );
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
