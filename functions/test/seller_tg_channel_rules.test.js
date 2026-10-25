/**
 * Сотувчининг ўз Telegram канали — Firestore rules (2026-10-25).
 *
 *   firebase emulators:exec --only firestore --project demo-seller-tg-rules \
 *     "node functions/test/seller_tg_channel_rules.test.js"
 *
 *   seller_tg_channels/{phone}       — эга фақат ўзиникини `get`; рўйхат/ёзиш йўқ (фақат callable)
 *   seller_tg_channel_chats/{chatId} — ҳеч ким (фақат сервер)
 *   tv_clips.socialNetworks 'seller_telegram' — фақат яратишда, «Рухсат бераман» (v ≥ 2) билан; кейин қўшиб
 *                                             бўлмайди; розиликни қайтариб олиш (олиб ташлаш) мумкин; эски клиент ўзгармайди
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const OWNER = '998905556677';
const OTHER = '998904445566';

function clip(extra = {}) {
  return {
    videoUrl: 'https://example.com/v.mp4', posterUrl: '', title: 'Non', price: 35000, districtId: 'gurlan',
    ownerPhone: OWNER, ownerName: 'Aziz', category: 'product', status: 'pending',
    socialConsent: false, socialNetworks: [], createdAt: new Date(), ...extra,
  };
}
const own = (extra = {}) => clip({
  socialConsent: true, socialNetworks: ['seller_telegram'], socialConsentAt: serverTimestamp(), socialConsentVersion: 2, ...extra,
});

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-seller-tg-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (p) => testEnv.authenticatedContext(`u${p}`, { phone_number: `+${p}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();

  async function reset() {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc(`seller_tg_channels/${OWNER}`).set({ ownerPhone: OWNER, status: 'connected', chatId: '-1001', username: 'non_shop' });
      await db.doc('seller_tg_channel_chats/-1001').set({ ownerPhone: OWNER, chatId: '-1001' });
      await db.doc('settings/app').set({ tvAutoApprove: false });
      await db.doc('tv_clips/withOwn').set(clip({ socialConsent: true, socialNetworks: ['seller_telegram'], socialConsentVersion: 2 }));
      await db.doc('tv_clips/plain').set(clip({ socialConsent: true, socialNetworks: ['telegram'], socialConsentVersion: 1 }));
      await db.doc('tv_clips/legacyOdd').set(clip({ socialNetworks: 'telegram' }));
    });
  }

  await reset();
  await check('R1 ega o\'z kanal hujjatini ID bilan o\'qiydi; begona, mehmon va ro\'yxat — yo\'q', async () => {
    await assertSucceeds(as(OWNER).doc(`seller_tg_channels/${OWNER}`).get());
    await assertSucceeds(as(OTHER).doc(`seller_tg_channels/${OTHER}`).get()); // hali yo'q hujjat — o'ziniki
    await assertFails(as(OTHER).doc(`seller_tg_channels/${OWNER}`).get());
    await assertFails(anon().doc(`seller_tg_channels/${OWNER}`).get());
    await assertFails(as(OWNER).collection('seller_tg_channels').get());
    await assertFails(as(OWNER).collection('seller_tg_channels').where('ownerPhone', '==', OWNER).get());
  });

  await check('R2 ega ham kanal hujjatini yoza olmaydi (status/chatId/kod — faqat server)', async () => {
    await assertFails(as(OWNER).doc(`seller_tg_channels/${OWNER}`).update({ status: 'connected', chatId: '-1002' }));
    await assertFails(as(OTHER).doc(`seller_tg_channels/${OTHER}`).set({ ownerPhone: OTHER, status: 'connected', chatId: '-1001' }));
    await assertFails(as(OWNER).doc(`seller_tg_channels/${OWNER}`).delete());
  });

  await check('R3 kanal -> sotuvchi indeksi: hech kim o\'qimaydi/yozmaydi (egallash yo\'li yo\'q)', async () => {
    await assertFails(as(OWNER).doc('seller_tg_channel_chats/-1001').get());
    await assertFails(as(OTHER).doc('seller_tg_channel_chats/-1001').set({ ownerPhone: OTHER }));
    await assertFails(as(OTHER).doc('seller_tg_channel_chats/-1001').delete());
    await assertFails(as(OWNER).collection('seller_tg_channel_chats').get());
  });

  await check('R4 klip yaratish: «Менинг каналим» + «Рухсат бераман» v2 — ruxsat; AVA tarmoqlari bilan birga ham', async () => {
    await assertSucceeds(as(OWNER).collection('tv_clips').add(own()));
    await assertSucceeds(as(OWNER).collection('tv_clips').add(own({ socialNetworks: ['telegram', 'seller_telegram'] })));
    await assertSucceeds(as(OWNER).collection('tv_clips').add(own({ category: 'service' })));
  });

  await check('R5 klip yaratish: kanal tanlangan, lekin rozilik yo\'q / eski matn versiyasi (1) / versiyasiz — rad', async () => {
    await assertFails(as(OWNER).collection('tv_clips').add(own({ socialConsent: false })));
    await assertFails(as(OWNER).collection('tv_clips').add(own({ socialConsentVersion: 1 })));
    const noVer = own();
    delete noVer.socialConsentVersion;
    delete noVer.socialConsentAt;
    await assertFails(as(OWNER).collection('tv_clips').add(noVer));
    await assertFails(as(OWNER).collection('tv_clips').add(own({ socialConsentVersion: '2' })));
  });

  await check('R6 eski ilova (kanalsiz) — o\'zgarmagan: AVA tarmoqlari v1 bilan, tarmoqsiz klip — ruxsat', async () => {
    await assertSucceeds(as(OWNER).collection('tv_clips').add(clip({
      socialConsent: true, socialNetworks: ['telegram'], socialConsentAt: serverTimestamp(), socialConsentVersion: 1,
    })));
    await assertSucceeds(as(OWNER).collection('tv_clips').add(clip()));
    await assertSucceeds(as(OWNER).collection('tv_clips').add(clip({ socialConsent: true, socialNetworks: ['instagram'] })));
  });

  await check('R7 keyin qo\'shib bo\'lmaydi: kanalsiz klipga seller_telegram — rad (rozilik bilan ham)', async () => {
    await assertFails(as(OWNER).doc('tv_clips/plain').update({ socialNetworks: ['telegram', 'seller_telegram'] }));
    await assertFails(as(OWNER).doc('tv_clips/plain').update({ socialNetworks: ['seller_telegram'], socialConsent: true }));
  });

  await check('R8 rozilikni qaytarib olish (kanal ham olib tashlanadi) va oddiy tahrir — ruxsat; begona — rad', async () => {
    await assertSucceeds(as(OWNER).doc('tv_clips/withOwn').update({ title: 'Yangi nom', price: 40000 }));
    await assertFails(as(OTHER).doc('tv_clips/withOwn').update({ socialConsent: false, socialNetworks: [] }));
    await assertSucceeds(as(OWNER).doc('tv_clips/withOwn').update({ socialConsent: false, socialNetworks: [] }));
    await assertFails(as(OWNER).doc('tv_clips/withOwn').update({ socialNetworks: ['seller_telegram'] }), 'olib tashlangach qayta qo\'shib bo\'lmaydi');
  });

  await check('R9 g\'alati eski hujjat (socialNetworks matn) — egasining oddiy tahriri buzilmaydi', async () => {
    await assertSucceeds(as(OWNER).doc('tv_clips/legacyOdd').update({ title: 'Tahrir' }));
  });

  await check('R10 natija maydonlari va rozilik vaqti/versiyasi — avvalgidek qulf', async () => {
    await assertFails(as(OWNER).doc('tv_clips/withOwn').update({ 'socialPost.networks.seller_telegram': { status: 'posted' } }));
    await assertFails(as(OWNER).doc('tv_clips/withOwn').update({ socialConsentVersion: 3 }));
    await assertFails(as(OWNER).doc('tv_clips/withOwn').update({ socialRetryAt: Date.now() }));
  });

  await testEnv.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
