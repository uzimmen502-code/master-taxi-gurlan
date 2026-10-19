/**
 * KO'CHMAS MULK — e'lon o'chirilsa uning AVAGram videosi ham o'chadi (ega qarori 2026-10-19).
 * HAQIQIY `functions/index.js`: `deleteRealtyListing` callable (egasi), `adminDeleteRealtyListing`
 * (admin) va `onRealtyListingDeleted` triggeri `.run()` orqali, Firestore Emulator.
 *
 *   powershell -File <scratch>\run-emu.ps1 -Project demo-realty-video -Node "node functions/test/realty_video_cleanup.test.js"
 *   (yoki: firebase emulators:exec --only firestore --project demo-realty-video "node functions/test/realty_video_cleanup.test.js")
 *
 * Qulflanadi:
 *   RV1  e'lonni egasi o'chirsa FAQAT shu e'lonning (linkKind realty_listing) klip(lar)i o'chadi —
 *        jamoa a'zosi yuklagani ham; boshqa e'lon/boshqa tur/bog'lanmagan klip saqlanadi; takror — xato yo'q
 *   RV2  admin o'chirsa ham; sotish va ijara e'loni bir xil (deal farqi yo'q)
 *   RV3  begona (ownerKey boshqa) e'lonni o'chira olmaydi — klip saqlanadi (ruxsat callable'da)
 *   RV4  eski yo'l: avagramClipId/adClipId bilan ulangan MUSTAQIL klipga tegilmaydi
 *   RV5  videosi yo'q e'lon — xato yo'q; 130 ta bog'langan klip (takror yuklash) ham to'liq o'chadi
 *   RV6  trigger FAQAT `realty_listings` o'chirishida ishlaydi: e'lon status 'blocked' bo'lishi klipni o'chirmaydi
 *        (hujjat o'chirilmaguncha trigger chaqirilmaydi) — «ўчирилди» = hujjat o'chirilishi
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-realty-video';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.DIRECTIONS_API_KEY = '';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();

const OWNER = '998911000001';
const TEAMMATE = '998911000002'; // bir xil realtyOwnerKey — jamoa hisobi
const STRANGER = '998914000001';
const ADMIN = '998915000001';
const KEY = 'ownerkeyAAAA';

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

const clips = () => db.collection('tv_clips');
const listings = () => db.collection('realty_listings');
const left = async (prefix) => (await clips().get()).docs.map((d) => d.id).filter((id) => id.startsWith(prefix)).sort();
const mkClip = (id, extra) => clips().doc(id).set({ ownerPhone: OWNER, status: 'active', category: 'product', ...extra });
const mkListing = (id, extra = {}) => listings().doc(id).set({
  ownerKey: KEY, ownerName: 'Али', deal: 'sale', tier: 'plain', title: 'Уй', text: 'Тавсиф',
  status: 'active', avagramClipId: '', adClipId: '', ...extra,
});
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
/** Haqiqiy o'chirish yo'li + triggerni qo'lda ishga tushirish (emulyatorda trigger o'zi yurmaydi). */
async function deleteThenTrigger(listingId, deleter) {
  const snap = await listings().doc(listingId).get();
  await deleter();
  assert.strictEqual((await listings().doc(listingId).get()).exists, false, 'e\'lon hujjati o\'chgan');
  await fns.onRealtyListingDeleted.run(snap, { params: { listingId } });
}

async function main() {
  await clearEmulator();
  await db.collection('users').doc(OWNER).set({ realtyOwnerKey: KEY });
  await db.collection('users').doc(TEAMMATE).set({ realtyOwnerKey: KEY });
  await db.collection('users').doc(STRANGER).set({ realtyOwnerKey: 'otherkey' });
  await db.collection('users').doc(ADMIN).set({ role: 'admin', name: 'Admin' });

  await check('RV1 egasi o\'chirsa FAQAT shu e\'lon klipi o\'chadi (jamoa a\'zosi yuklagani ham); boshqasi saqlanadi; takror — xato yo\'q', async () => {
    await mkListing('L1', { deal: 'sale' });
    await mkListing('L2', { deal: 'rent' });
    await mkClip('rv1_a', { linkKind: 'realty_listing', linkId: 'L1' });
    await mkClip('rv1_b', { linkKind: 'realty_listing', linkId: 'L1', status: 'pending', ownerPhone: TEAMMATE });
    await mkClip('rv1_other_listing', { linkKind: 'realty_listing', linkId: 'L2' });
    await mkClip('rv1_ad', { linkKind: 'ad', linkId: 'L1' }); // boshqa tur, linkId tasodifan bir xil
    await mkClip('rv1_rest', { linkKind: 'restaurant', linkId: 'L1' });
    await mkClip('rv1_plain', {});
    await deleteThenTrigger('L1', () => fns.deleteRealtyListing.run({ listingId: 'L1' }, ctxOf(OWNER)));
    const expected = ['rv1_ad', 'rv1_other_listing', 'rv1_plain', 'rv1_rest'];
    assert.deepStrictEqual(await left('rv1_'), expected);
    // takror (retry): topiladigan klip yo'q, xato yo'q, boshqasi yana tegilmagan
    await fns.onRealtyListingDeleted.run(await listings().doc('L2').get(), { params: { listingId: 'L1' } });
    assert.deepStrictEqual(await left('rv1_'), expected);
    assert.strictEqual((await listings().doc('L2').get()).exists, true, 'boshqa e\'lon tegilmagan');
  });

  await check('RV2 admin o\'chirsa ham klip o\'chadi; ijara e\'loni ham (sotish bilan bir xil)', async () => {
    await mkListing('L3', { deal: 'rent' });
    await mkClip('rv2_a', { linkKind: 'realty_listing', linkId: 'L3' });
    await mkClip('rv2_keep', { linkKind: 'realty_listing', linkId: 'L2' });
    await deleteThenTrigger('L3', () => fns.adminDeleteRealtyListing.run({ listingId: 'L3', adminPhone: ADMIN }, ctxOf(ADMIN)));
    assert.deepStrictEqual(await left('rv2_'), ['rv2_keep']);
  });

  await check('RV3 begona e\'lonni o\'chira olmaydi (callable rad etadi) — klip saqlanadi', async () => {
    await mkListing('L4');
    await mkClip('rv3_a', { linkKind: 'realty_listing', linkId: 'L4' });
    await assert.rejects(
      fns.deleteRealtyListing.run({ listingId: 'L4' }, ctxOf(STRANGER)),
      (e) => e.code === 'permission-denied',
    );
    assert.strictEqual((await listings().doc('L4').get()).exists, true);
    assert.deepStrictEqual(await left('rv3_'), ['rv3_a']);
  });

  await check('RV4 eski yo\'l (avagramClipId/adClipId) bilan ulangan mustaqil klipga TEGILMAYDI', async () => {
    await mkClip('rv4_free', {}); // oddiy AVAGram klipi
    await mkClip('rv4_paid', { category: 'ad' }); // pullik reklama klipi
    await mkListing('L5', { avagramClipId: 'rv4_free', adClipId: 'rv4_paid' });
    await mkClip('rv4_new', { linkKind: 'realty_listing', linkId: 'L5' });
    await deleteThenTrigger('L5', () => fns.deleteRealtyListing.run({ listingId: 'L5' }, ctxOf(OWNER)));
    assert.deepStrictEqual(await left('rv4_'), ['rv4_free', 'rv4_paid']);
  });

  await check('RV5 videosi yo\'q e\'lon — xato yo\'q; 130 ta bog\'langan klip ham to\'liq o\'chadi', async () => {
    await mkListing('L6');
    await fns.onRealtyListingDeleted.run(await listings().doc('L6').get(), { params: { listingId: 'L6' } });
    await fns.onRealtyListingDeleted.run(await listings().doc('L6').get(), { params: { listingId: 'yo_q_elon' } });
    const batchSize = 130;
    for (let i = 0; i < batchSize; i += 100) {
      const b = db.batch();
      for (let j = i; j < Math.min(i + 100, batchSize); j += 1) {
        b.set(clips().doc(`rv5_many_${j}`), { ownerPhone: OWNER, status: 'active', linkKind: 'realty_listing', linkId: 'MANY' });
      }
      await b.commit();
    }
    await fns.onRealtyListingDeleted.run(await listings().doc('L6').get(), { params: { listingId: 'MANY' } });
    assert.strictEqual((await clips().where('linkId', '==', 'MANY').get()).size, 0);
  });

  await check('RV6 «ўчирилди» = hujjat o\'chishi: status blocked/pending klipni o\'chirmaydi (adminSetRealtyStatus)', async () => {
    await mkListing('L7');
    await mkClip('rv6_a', { linkKind: 'realty_listing', linkId: 'L7' });
    await fns.adminSetRealtyStatus.run({ listingId: 'L7', status: 'blocked', adminPhone: ADMIN }, ctxOf(ADMIN));
    assert.strictEqual((await listings().doc('L7').get()).data().status, 'blocked');
    assert.deepStrictEqual(await left('rv6_'), ['rv6_a']);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
