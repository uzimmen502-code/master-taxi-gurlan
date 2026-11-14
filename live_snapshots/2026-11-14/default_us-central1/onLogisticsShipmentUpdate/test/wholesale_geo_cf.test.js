/**
 * `wholesale_geo.js` — товар ҳудуди (сотувчи манзилидан) ва эски синов
 * товарларини яшириш (D-GEO-10/14, 2026-10-11). Firestore Emulator:
 *   firebase emulators:exec --only firestore --project demo-wholesale-geo \
 *     "node functions/test/wholesale_geo_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wholesale-geo';

const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const wg = require('../wholesale_geo');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const quiet = { log: () => {} };
const ts = (m) => admin.firestore.Timestamp.fromMillis(m);
const CUTOFF = Date.UTC(2026, 9, 12, 0, 0);
const H = 3600 * 1000;

async function wipe(col) {
  const docs = await db.collection(col).listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
}
const prod = (id) => db.collection('wholesale_products').doc(id);
const get = async (id) => (await prod(id).get()).data();

(async () => {
  await Promise.all(['wholesale_products', 'wholesale_sellers', 'settings', 'admin_audit'].map(wipe));

  // ─── Ҳудуд ──────────────────────────────────────────────────────────
  await db.doc('wholesale_sellers/S1').set({ phone: 'S1', regionId: 'xorazm', districtId: 'gurlan' });
  await db.doc('wholesale_sellers/S2').set({ phone: 'S2' }); // манзилсиз
  await prod('p1').set({ sellerId: 'S1', status: 'active', market: 'wholesale' });
  await prod('p2').set({ sellerId: 'S2', status: 'active' });

  await check('G1 товарга сотувчи ҳудуди ёзилади', async () => {
    assert.strictEqual(await wg.syncProductGeo(db, admin, prod('p1'), await get('p1')), true);
    const d = await get('p1');
    assert.deepStrictEqual([d.regionId, d.districtId], ['xorazm', 'gurlan']);
  });
  await check('G2 такрор — ёзилмайди (фарқ йўқ)', async () => {
    assert.strictEqual(await wg.syncProductGeo(db, admin, prod('p1'), await get('p1')), false);
  });
  await check('G3 манзилсиз сотувчи — ҳудуд йўқ (фақат «Бутун Ўзбекистон»да)', async () => {
    await wg.syncProductGeo(db, admin, prod('p2'), await get('p2'));
    const d = await get('p2');
    assert.ok(!('districtId' in d) && !('regionId' in d));
  });
  await check('G4 сотувчи манзилини ўзгартирди — барча товарлари янгиланади', async () => {
    await prod('p3').set({ sellerId: 'S1', status: 'pending', regionId: 'xorazm', districtId: 'gurlan' });
    const n = await wg.syncSellerProducts(db, admin, 'S1', { regionId: 'xorazm', districtId: 'xiva' });
    assert.strictEqual(n, 2);
    assert.strictEqual((await get('p1')).districtId, 'xiva');
    assert.strictEqual((await get('p3')).districtId, 'xiva');
  });

  // ─── Эски синов товарлари ───────────────────────────────────────────
  await wipe('wholesale_products');
  await check('L1 биринчи ишга тушиш — чегара сана ёзилади, ҳеч нарса яширилмайди', async () => {
    const r = await wg.runLegacyCleanup(db, admin, { now: CUTOFF, ...quiet });
    assert.strictEqual(r.initialized, true);
    const app = (await db.doc('settings/app').get()).data();
    assert.strictEqual(app.wholesaleLegacyCutoff.toMillis(), CUTOFF);
  });

  // 25 та эски (cutoff'дан олдин): 15 улгуржи (5 тасида market йўқ) + 10 Хитой.
  for (let i = 0; i < 15; i += 1) {
    await prod(`old_w${i}`).set({
      status: 'active', createdAt: ts(CUTOFF - (100 - i) * H), ...(i < 5 ? {} : { market: 'wholesale' }),
      ...(i === 0 ? { adminNote: 'moderator izohi' } : {}),
    });
  }
  for (let i = 0; i < 10; i += 1) {
    await prod(`old_c${i}`).set({ status: 'active', market: 'china', createdAt: ts(CUTOFF - (50 - i) * H) });
  }
  const addNew = async (n, market, from = 0) => {
    for (let i = from; i < from + n; i += 1) {
      await prod(`new_${market}${i}`).set({ status: 'active', market, createdAt: ts(CUTOFF + (i + 1) * H) });
    }
  };
  const archivedIds = async () => (await db.collection('wholesale_products').where('legacyArchived', '==', true).get())
    .docs.map((d) => d.id).sort();

  await check('L2 янги 9 та — ҳали яширилмайди', async () => {
    await addNew(9, 'wholesale');
    const r = await wg.runLegacyCleanup(db, admin, quiet);
    assert.deepStrictEqual(r.archived, { wholesale: 0 });
    assert.deepStrictEqual(await archivedIds(), []);
  });
  await check('L3 10-чи — 10 та ЭНГ ЭСКИ улгуржи яширилади (market йўқлари ҳам), Хитойга тегмайди', async () => {
    await addNew(1, 'wholesale', 9);
    const r = await wg.runLegacyCleanup(db, admin, quiet);
    assert.deepStrictEqual(r.archived, { wholesale: 10 });
    const ids = await archivedIds();
    assert.strictEqual(ids.length, 10);
    assert.ok(ids.every((id) => id.startsWith('old_w')));
    for (let i = 0; i < 10; i += 1) assert.ok(ids.includes(`old_w${i}`), `old_w${i}`);
    const d = await get('old_w0');
    assert.strictEqual(d.status, 'inactive');
    assert.strictEqual(d.adminNote, 'legacy_test_cleanup');
  });
  await check('L3b аввалги adminNote ва status сақланади (қайтариш учун)', async () => {
    const d0 = await get('old_w0');
    assert.strictEqual(d0.legacyPrevAdminNote, 'moderator izohi');
    assert.strictEqual(d0.legacyPrevStatus, 'active');
    const d1 = await get('old_w1');
    assert.strictEqual(d1.legacyPrevAdminNote, null, 'изоҳ йўқ эди — null');
  });
  await check('L4 такрор ишга тушиш — ортиқча яширмайди (idempotent)', async () => {
    const r = await wg.runLegacyCleanup(db, admin, quiet);
    assert.deepStrictEqual(r.archived, { wholesale: 0 });
    assert.strictEqual((await archivedIds()).length, 10);
  });
  await check('L4b админ қайта ёққан товар қайта яширилмайди ва ўрнига бошқаси ҳам яширилмайди', async () => {
    await prod('old_w3').update({ status: 'active', adminNote: 'admin qaytardi' });
    const r = await wg.runLegacyCleanup(db, admin, quiet);
    assert.deepStrictEqual(r.archived, { wholesale: 0 });
    const d = await get('old_w3');
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.adminNote, 'admin qaytardi');
    assert.strictEqual((await get('old_w10')).status, 'active');
  });
  await check('L5 янги 12 та — жами 12 эски; эски тугаса тўхтайди', async () => {
    await addNew(2, 'wholesale', 10);
    await wg.runLegacyCleanup(db, admin, quiet);
    assert.strictEqual((await archivedIds()).filter((id) => id.startsWith('old_w')).length, 12);
    await addNew(20, 'wholesale', 12); // 32 янги, эски атиги 15
    await wg.runLegacyCleanup(db, admin, quiet);
    assert.strictEqual((await archivedIds()).filter((id) => id.startsWith('old_w')).length, 15);
  });
  await check('L6 Хитой ҲЕЧ ҚАЧОН яширилмайди (эга: «Хитойдаги ҳақиқий»), 10 та янги Хитой бўлса ҳам', async () => {
    await addNew(10, 'china');
    const r = await wg.runLegacyCleanup(db, admin, quiet);
    assert.ok(!('china' in r.archived));
    assert.strictEqual((await archivedIds()).filter((id) => id.startsWith('old_c')).length, 0);
    for (let i = 0; i < 10; i += 1) assert.strictEqual((await get(`old_c${i}`)).status, 'active');
  });
  await check('L7 audit ёзуви бор (admin_audit)', async () => {
    const a = await db.collection('admin_audit').where('kind', '==', 'wholesale_legacy_archive').get();
    assert.ok(a.size >= 3);
    const one = a.docs[0].data();
    assert.ok(Array.isArray(one.productIds) && one.productIds.length > 0);
  });
  await check('L8 янги товарлар ва AVA эмас (яширилмаган)', async () => {
    assert.strictEqual((await get('new_wholesale0')).status, 'active');
  });

  // ─── Қайтариш (rollback) ────────────────────────────────────────────
  await check('R1 DRY-RUN — ҳеч нарса ёзмайди, номзодлар = яширилган ҳолатдагилар', async () => {
    const before = (await get('old_w0')).status;
    const r = await wg.restoreLegacyArchived(db, admin);
    assert.strictEqual(r.applied, false);
    assert.strictEqual(r.restored, 0);
    assert.ok(r.candidates.includes('old_w0'));
    assert.ok(!r.candidates.includes('old_w3'), 'админ қайтаргани — номзод эмас');
    assert.strictEqual((await get('old_w0')).status, before);
  });
  await check('R2 APPLY — аввалги status/adminNote қайтади, белги қолади (қайта яширилмайди)', async () => {
    const r = await wg.restoreLegacyArchived(db, admin, { apply: true, ids: ['old_w0', 'old_w1'] });
    assert.strictEqual(r.restored, 2);
    const d0 = await get('old_w0');
    assert.strictEqual(d0.status, 'active');
    assert.strictEqual(d0.adminNote, 'moderator izohi');
    assert.strictEqual(d0.legacyArchived, true);
    const d1 = await get('old_w1');
    assert.ok(!('adminNote' in d1), 'изоҳ йўқ эди — ўчирилади');
    const again = await wg.runLegacyCleanup(db, admin, quiet);
    assert.deepStrictEqual(again.archived, { wholesale: 0 });
    assert.strictEqual((await get('old_w0')).status, 'active');
    const a = await db.collection('admin_audit').where('kind', '==', 'wholesale_legacy_restore').get();
    assert.strictEqual(a.size, 1);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} wholesale geo checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
