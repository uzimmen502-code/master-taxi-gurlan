/**
 * «Бозорлар» 1-босқич (2026-11-15) — tv_shop_items ихтиёрий бозор майдонлари ва taxonomy / taxonomy_history қоидалари.
 *
 *   firebase emulators:exec --only firestore --project demo-market-rules \
 *     "node test/tv_shop_items_market_rules.test.js"
 *   (бошқа қоида матнини синаш: RULES_FILE=<йўл>)
 *
 * market ∈ livestock|auto|meat|farm; category фақат market билан (1..40); attrs map ≤ 20 калит; imported bool;
 * regionId 1..40; taxonomyVersion int ≥ 1. Эски (майдонсиз) товар ўзгаришсиз ўтади.
 * taxonomy — ҳамма ўқийди, клиент (admin ҳам) ёза олмайди; taxonomy_history — фақат admin ўқийди.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE
  ? path.resolve(process.env.RULES_FILE)
  : path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const OWNER = '998901112233';
const ADMIN = '998901110000';
const USER = '998912000001';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-market-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const owner = () => as(OWNER);
  const items = () => owner().collection('tv_shop_items');
  const item = (extra = {}) => ({
    ownerPhone: OWNER, title: 'Qo\'y', description: '', price: 3500000, photoUrls: [], clipIds: [],
    kind: 'product', status: 'active', viewCount: 0, ...extra,
  });
  const marketFields = (extra = {}) => ({
    market: 'livestock', category: 'all', attrs: { breed: 'Hisori', count: 2, pregnant: true },
    imported: false, regionId: 'xorazm', taxonomyVersion: 1, priceUnit: 'piece', ...extra,
  });

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(USER).set({ role: 'user' });
    await db.collection('users').doc(OWNER).set({ role: 'user' });
    await db.collection('taxonomy').doc('markets').set({ version: 1, markets: {} });
    await db.collection('taxonomy_history').doc('v1').set({ version: 1, markets: {} });
  });

  // ── tv_shop_items ──
  await check('M1 эски товар (янги майдонларсиз) — яратилади ва таҳрирланади', async () => {
    await assertSucceeds(items().doc('legacy').set(item()));
    await assertSucceeds(items().doc('legacy').update({ title: 'Qo\'y (2)' }));
  });
  await check('M2 тўлиқ бозор майдонлари (4 бозорнинг ҳар бири) — яратилади', async () => {
    await assertSucceeds(items().doc('m_l').set(item(marketFields())));
    await assertSucceeds(items().doc('m_a').set(item(marketFields({ market: 'auto', category: 'parts', attrs: { fits_car: 'Nexia 3', condition: 'used' }, priceUnit: '' }))));
    await assertSucceeds(items().doc('m_m').set(item(marketFields({ market: 'meat', category: 'beef', imported: true, attrs: { slaughter_date: '2026-11-14' }, priceUnit: 'kg' }))));
    await assertSucceeds(items().doc('m_f').set(item(marketFields({ market: 'farm', category: 'melons', attrs: {}, priceUnit: 'kg' }))));
  });
  await check('M3 attrs 20 калит — ўтади (чегара)', async () => {
    const attrs = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`k${i}`, i]));
    await assertSucceeds(items().doc('m_20').set(item(marketFields({ attrs }))));
  });
  await check('M4 эгаси бозор майдонларини таҳрирлайди (category, attrs, taxonomyVersion 2) — ўтади', async () => {
    await assertSucceeds(items().doc('m_l').update({ category: 'all', attrs: { count: 5 }, taxonomyVersion: 2 }));
    await assertSucceeds(items().doc('legacy').update({ market: 'farm', category: 'grain' }));
  });
  await check('M5 market рўйхатда йўқ / сатр эмас / null — рад', async () => {
    await assertFails(items().doc('x1').set(item(marketFields({ market: 'fish' }))));
    await assertFails(items().doc('x2').set(item(marketFields({ market: 3 }))));
    await assertFails(items().doc('x3').set(item(marketFields({ market: null }))));
  });
  await check('M6 category market\'сиз / бўш / 41 белги / сатр эмас — рад', async () => {
    await assertFails(items().doc('x4').set(item({ category: 'beef' })));
    await assertFails(items().doc('x5').set(item(marketFields({ category: '' }))));
    await assertFails(items().doc('x6').set(item(marketFields({ category: 'c'.repeat(41) }))));
    await assertFails(items().doc('x7').set(item(marketFields({ category: ['beef'] }))));
    await assertSucceeds(items().doc('x8').set(item(marketFields({ category: 'c'.repeat(40) }))));
  });
  await check('M7 attrs 21 калит / рўйхат — рад', async () => {
    const attrs = Object.fromEntries(Array.from({ length: 21 }, (_, i) => [`k${i}`, i]));
    await assertFails(items().doc('x9').set(item(marketFields({ attrs }))));
    await assertFails(items().doc('x10').set(item(marketFields({ attrs: ['a'] }))));
  });
  await check('M8 imported bool эмас — рад', async () => {
    await assertFails(items().doc('x11').set(item(marketFields({ imported: 'yes' }))));
    await assertFails(items().doc('x12').set(item(marketFields({ imported: 1 }))));
  });
  await check('M9 taxonomyVersion 0 / каср / сатр — рад', async () => {
    await assertFails(items().doc('x13').set(item(marketFields({ taxonomyVersion: 0 }))));
    await assertFails(items().doc('x14').set(item(marketFields({ taxonomyVersion: 1.5 }))));
    await assertFails(items().doc('x15').set(item(marketFields({ taxonomyVersion: '1' }))));
  });
  await check('M10 regionId бўш / 41 белги — рад', async () => {
    await assertFails(items().doc('x16').set(item(marketFields({ regionId: '' }))));
    await assertFails(items().doc('x17').set(item(marketFields({ regionId: 'r'.repeat(41) }))));
  });
  await check('M11 эгаси таҳририда ҳам: market нотўғри, category\'ни market\'сиз қолдириш, attrs 21 — рад', async () => {
    await assertFails(items().doc('m_l').update({ market: 'cars' }));
    await assertFails(items().doc('legacy2').set(item({ category: 'x' })));
    await assertSucceeds(items().doc('legacy3').set(item()));
    await assertFails(items().doc('legacy3').update({ category: 'beef' }));
    const attrs = Object.fromEntries(Array.from({ length: 21 }, (_, i) => [`k${i}`, i]));
    await assertFails(items().doc('m_l').update({ attrs }));
    await assertFails(items().doc('m_l').update({ taxonomyVersion: 0 }));
  });

  // ── taxonomy ──
  await check('M12 янги бозорлар electronics / appliances (эга 2026-11-16) — яратилади ва таҳрирда ўтади', async () => {
    await assertSucceeds(items().doc('m_e').set(item(marketFields({ market: 'electronics', category: 'phones', attrs: { brand: 'Samsung', condition: 'new', warranty_months: 12, storage_gb: 256 }, taxonomyVersion: 2 }))));
    await assertSucceeds(items().doc('m_ap').set(item(marketFields({ market: 'appliances', category: 'climate', attrs: { brand: 'Artel', condition: 'used' }, priceUnit: '', taxonomyVersion: 2 }))));
    await assertSucceeds(items().doc('m_f').update({ market: 'appliances', category: 'large' }));
  });
  await check('M13 номаълум бозор (furniture, Electronics, electronics_market) — рад, таҳрирда ҳам', async () => {
    await assertFails(items().doc('x_e1').set(item(marketFields({ market: 'furniture' }))));
    await assertFails(items().doc('x_e2').set(item(marketFields({ market: 'Electronics' }))));
    await assertFails(items().doc('x_e3').set(item(marketFields({ market: 'electronics_market' }))));
    await assertFails(items().doc('m_e').update({ market: 'furniture' }));
  });
  await check('M14 taxonomy v5 (эга 2026-11-19): мол янги бўлимлари + эски `all` таҳрирда қолади; box_*_cm int attrs — ўтади', async () => {
    await assertSucceeds(items().doc('m_v5l').set(item(marketFields({ category: 'sheep_goat', attrs: { age_months: 14, count: 3 }, taxonomyVersion: 5 }))));
    await assertSucceeds(items().doc('m_l').update({ title: 'Eski all', category: 'all' }));
    await assertSucceeds(items().doc('m_l').update({ category: 'cattle', taxonomyVersion: 5 }));
    await assertSucceeds(items().doc('m_v5e').set(item(marketFields({
      market: 'electronics', category: 'tv', priceUnit: '', taxonomyVersion: 5,
      attrs: { brand: 'LG', model: 'X', condition: 'new', warranty_months: 12, storage_gb: 8, box_w_cm: 1, box_l_cm: 1000, box_h_cm: 70 },
    }))));
    await assertSucceeds(items().doc('m_ap').update({ attrs: { brand: 'Artel', box_w_cm: 60, box_l_cm: 60, box_h_cm: 180 } }));
  });
  await check('T1 taxonomy: ҳамма ўқийди (меҳмон, user, admin)', async () => {
    await assertSucceeds(testEnv.unauthenticatedContext().firestore().collection('taxonomy').doc('markets').get());
    await assertSucceeds(as(USER).collection('taxonomy').doc('markets').get());
    await assertSucceeds(as(ADMIN).collection('taxonomy').doc('markets').get());
  });
  await check('T2 taxonomy: клиент ёза олмайди — admin токени билан ҳам (set/update/delete/янги ҳужжат)', async () => {
    await assertFails(as(ADMIN).collection('taxonomy').doc('markets').set({ version: 2, markets: {} }));
    await assertFails(as(ADMIN).collection('taxonomy').doc('markets').update({ version: 2 }));
    await assertFails(as(ADMIN).collection('taxonomy').doc('markets').delete());
    await assertFails(as(ADMIN).collection('taxonomy').doc('other').set({ a: 1 }));
    await assertFails(as(USER).collection('taxonomy').doc('markets').set({ version: 2 }));
  });
  await check('T3 taxonomy_history: admin ўқийди; user/меҳмон — рад; ҳеч ким ёза олмайди', async () => {
    await assertSucceeds(as(ADMIN).collection('taxonomy_history').doc('v1').get());
    await assertSucceeds(as(ADMIN).collection('taxonomy_history').get());
    await assertFails(as(USER).collection('taxonomy_history').doc('v1').get());
    await assertFails(testEnv.unauthenticatedContext().firestore().collection('taxonomy_history').doc('v1').get());
    await assertFails(as(ADMIN).collection('taxonomy_history').doc('v2').set({ version: 2 }));
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(2); });
