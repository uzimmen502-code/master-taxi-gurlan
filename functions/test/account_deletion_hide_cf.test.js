/**
 * HISOBNI O'CHIRISH — "darhol yashirish" va qaytarish (`account_deletion_hide.js`), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-hide \
 *     "node test/account_deletion_hide_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-del-hide';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const core = require('../account_deletion_core');
const { createHider, HIDE_RULES, MARK } = require('../account_deletion_hide');
const { createAccountDeletion } = require('../account_deletion');

const U = '998901112233';
const U9 = '901112233';
const OTHER = '998907776655';

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const data = async (path) => (await db.doc(path).get()).data();
const hider = () => createHider({ db, admin });
const ident = () => core.resolveIdentity(db, U);

async function seed() {
  await clearEmulator();
  await db.collection('users').doc(U).set({ role: 'user', phone: `+${U}`, realtyOwnerKey: 'rk1' });
  await db.collection('users').doc(OTHER).set({ role: 'user', phone: `+${OTHER}` });
  await db.collection('ads').doc('a1').set({ ownerId: U, status: 'active', type: 'cheap_product' });
  await db.collection('ads').doc('a2').set({ ownerId: U, status: 'pending' });
  await db.collection('ads').doc('a3').set({ ownerId: OTHER, status: 'active' });
  await db.collection('ads').doc('a4').set({ authorPhone: U, status: 'active', type: 'work' });
  await db.collection('tv_clips').doc('c1').set({ ownerPhone: U, status: 'active' });
  await db.collection('tv_clips').doc('c2').set({ ownerPhone: U, status: 'pending' });
  await db.collection('tv_clips').doc('c3').set({ ownerPhone: U9, status: 'active' }); // eski 9 xonali shakl
  await db.collection('tv_clips').doc('c4').set({ ownerPhone: OTHER, status: 'active' });
  await db.collection('tv_shop_items').doc('i1').set({ ownerPhone: U, status: 'active' });
  await db.collection('yuk_listings').doc('y1').set({ ownerId: U, status: 'active' });
  await db.collection('wholesale_products').doc('w1').set({ sellerId: U, status: 'active' });
  await db.collection('realty_listings').doc('r1').set({ ownerKey: 'rk1', status: 'active' });
  await db.collection('realty_listings').doc('r2').set({ ownerKey: 'rk_other', status: 'active' });
  await db.collection('ev_charging_stations').doc('e1').set({ createdBy: U, isActive: true });
  await db.collection('ev_charging_stations').doc('e2').set({ createdBy: '', isActive: true });
  await db.collection('schedules').doc('s1').set({ driverId: U, isActive: true });
  await db.collection('queue').doc(U).set({ isActive: true, driverPhone: U });
  await db.collection('intercity_drivers').doc(U).set({ isActive: true });
  await db.collection('dating_profiles').doc(U).set({ displayName: 'Ali' }); // active yo'q = faol
  await db.collection('dating_profiles').doc(OTHER).set({ displayName: 'Vali', active: true });
}
const recs = async () => (await db.collection('account_deletions').doc(U).collection('hidden').get()).docs.map((d) => d.data());

async function main() {
  await seed();

  await check('H1 qoidalar ro\'yxati: nomlar takrorsiz, har birida hideTo kiymati kuzatiladigan (visible) qiymatdan farq qiladi', () => {
    const names = HIDE_RULES.map((r) => r.name);
    assert.strictEqual(new Set(names).size, names.length);
    for (const r of HIDE_RULES) {
      if (r.visible) for (const v of r.visible) assert.notStrictEqual(r.hideTo, v, r.name);
    }
    assert.ok(HIDE_RULES.find((r) => r.name === 'tv_clips').hideTo === 'expired'); // 'blocked' egaga push yuboradi
  });

  await check('H2 hide: faqat ko\'rinadigan hujjatlar yashiriladi; pending va begona tegilmaydi; belgi va yozuvlar', async () => {
    const r = await hider().hide(await ident());
    assert.ok(r.hidden >= 13, `yashirilgan: ${r.hidden}`);
    assert.strictEqual((await data('ads/a1')).status, 'inactive');
    assert.strictEqual((await data('ads/a1'))[MARK], true);
    assert.strictEqual((await data('ads/a4')).status, 'inactive'); // ish e'loni (authorPhone)
    assert.strictEqual((await data('ads/a2')).status, 'pending');  // allaqachon ko'rinmaydi
    assert.ok(!(MARK in (await data('ads/a2'))));
    assert.strictEqual((await data('ads/a3')).status, 'active');   // begona
    assert.strictEqual((await data('tv_clips/c1')).status, 'expired');
    assert.strictEqual((await data('tv_clips/c2')).status, 'pending');
    assert.strictEqual((await data('tv_clips/c3')).status, 'expired'); // 9 xonali shakl
    assert.strictEqual((await data('tv_clips/c4')).status, 'active');
    assert.strictEqual((await data('tv_shop_items/i1')).status, 'blocked');
    assert.strictEqual((await data('yuk_listings/y1')).status, 'closed');
    assert.strictEqual((await data('wholesale_products/w1')).status, 'inactive');
    assert.strictEqual((await data('realty_listings/r1')).status, 'blocked');
    assert.strictEqual((await data('realty_listings/r2')).status, 'active');
    assert.strictEqual((await data('ev_charging_stations/e1')).isActive, false);
    assert.strictEqual((await data('ev_charging_stations/e2')).isActive, true); // createdBy '' — begona
    assert.strictEqual((await data('schedules/s1')).isActive, false);
    assert.strictEqual((await data(`queue/${U}`)).isActive, false);
    assert.strictEqual((await data(`intercity_drivers/${U}`)).isActive, false);
    assert.strictEqual((await data(`dating_profiles/${U}`)).active, false);
    assert.strictEqual((await data(`dating_profiles/${OTHER}`)).active, true);
    const rs = await recs();
    assert.strictEqual(rs.length, r.hidden);
    assert.strictEqual(rs.find((x) => x.id === 'a1').prev, 'active');
    assert.strictEqual(rs.find((x) => x.rule === 'dating_profiles').prev, null); // active maydoni yo'q edi
  });

  await check('H3 hide takror chaqirilsa — yozuvlar ko\'paymaydi, prev o\'zgarmaydi (idempotent)', async () => {
    const before = await recs();
    const r = await hider().hide(await ident());
    assert.strictEqual(r.hidden, 0);
    const after = await recs();
    assert.strictEqual(after.length, before.length);
    assert.strictEqual(after.find((x) => x.id === 'a1').prev, 'active'); // 'inactive' bilan ustiga yozilmadi
  });

  await check('H4 unhide: hammasi qaytadi (dating active=true), belgilar olinadi, yozuvlar restored', async () => {
    const r = await hider().unhide(await ident());
    assert.ok(r.restored >= 13 && r.skipped === 0, JSON.stringify(r));
    assert.strictEqual((await data('ads/a1')).status, 'active');
    assert.ok(!(MARK in (await data('ads/a1'))));
    assert.strictEqual((await data('tv_clips/c1')).status, 'active');
    assert.strictEqual((await data('tv_clips/c2')).status, 'pending');
    assert.strictEqual((await data('realty_listings/r1')).status, 'active');
    assert.strictEqual((await data('ev_charging_stations/e1')).isActive, true);
    assert.strictEqual((await data(`dating_profiles/${U}`)).active, true);
    assert.ok((await recs()).every((x) => x.restored === true));
  });

  await check('H5 unhide takror — zarar yo\'q (0 ta)', async () => {
    const r = await hider().unhide(await ident());
    assert.deepStrictEqual(r, { restored: 0, skipped: 0 });
  });

  await check('H6 admin yashirilganni o\'zgartirgan bo\'lsa — unhide tegmaydi (boshqalarni qaytaradi)', async () => {
    await seed();
    await hider().hide(await ident());
    await db.collection('ads').doc('a1').update({ status: 'blocked' }); // admin bloklagan
    await db.collection('tv_clips').doc('c1').update({ [MARK]: admin.firestore.FieldValue.delete() }); // belgi yo'qolgan
    const r = await hider().unhide(await ident());
    assert.strictEqual(r.skipped, 2);
    assert.strictEqual((await data('ads/a1')).status, 'blocked');
    assert.strictEqual((await data('tv_clips/c1')).status, 'expired');
    assert.strictEqual((await data('yuk_listings/y1')).status, 'active');
  });

  await check('H7 hujjat orada o\'chib ketgan bo\'lsa unhide yiqilmaydi, arvoh hujjat yaratilmaydi', async () => {
    await seed();
    await hider().hide(await ident());
    await db.collection('ads').doc('a1').delete();
    const r = await hider().unhide(await ident());
    assert.ok(r.skipped >= 1);
    assert.strictEqual((await db.doc('ads/a1').get()).exists, false);
  });

  await check('H8 xizmat bilan: so\'rov → yashirildi; bekor qilish → qaytdi; hidePending belgisi yo\'q', async () => {
    await seed();
    await db.collection('settings').doc('account_deletion').set({ enabled: true });
    const svc = createAccountDeletion({
      db, admin, auth: { getUserByPhoneNumber: async () => { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; }, deleteUser: async () => {} },
      hiders: [hider()], now: () => 1_800_000_000_000, log: () => {},
    });
    await svc.request(U);
    assert.strictEqual((await data('ads/a1')).status, 'inactive');
    assert.strictEqual((await data('tv_clips/c1')).status, 'expired');
    assert.strictEqual((await data('account_deletions/' + U)).hidePending, undefined);
    await svc.cancel(U);
    assert.strictEqual((await data('ads/a1')).status, 'active');
    assert.strictEqual((await data('tv_clips/c1')).status, 'active');
    assert.strictEqual((await data(`dating_profiles/${U}`)).active, true);
  });

  await check('H9 skan chegarasidan ko\'p hujjat bo\'lsa HIDE_PARTIAL xatosi (jimgina tashlab ketmaydi), qolganlari baribir yashiriladi', async () => {
    await seed();
    for (let i = 0; i < 4; i++) await db.collection('ads').doc(`bulk${i}`).set({ ownerId: U, status: 'active' });
    const small = createHider({ db, admin, maxDocsPerRule: 3 });
    const id = await ident();
    let err = null;
    try { await small.hide(id); } catch (e) { err = e; }
    assert.ok(err && /^HIDE_PARTIAL:ads_market/.test(err.message), `xato: ${err && err.message}`);
    assert.ok(err.result.hidden > 0, 'boshqa qoidalar yashirilishi kerak edi');
    assert.strictEqual((await data('tv_clips/c1')).status, 'expired');
  });
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
