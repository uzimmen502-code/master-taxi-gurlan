/**
 * «Бозорлар» 2a (эга 2026-11-15) — Firestore rules: модерация/муддат майдонлари қулфи ва Улгуржи контент таҳрири.
 *
 *   firebase emulators:exec --only firestore --project demo-market-moderation-rules \
 *     "node test/market_moderation_rules.test.js"
 *   (бошқа қоида матнини синаш: RULES_FILE=<йўл>)
 *
 * tv_shop_items: яратишда (active/pending эски APK учун ҳам) модерация майдонлари тақиқ; эга таҳририда улар қулф;
 *   эга `active` қила олмайди (expired/rejected/pending → active йўқ), лекин истаган ҳолатдан `deleted` — мумкин.
 * wholesale_products: эга контентни ўзгартирса status `pending` ёки `inactive` бўлиши шарт.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE
  ? path.resolve(process.env.RULES_FILE)
  : path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const OWNER = '998901112233';
const ADMIN = '998901110000';
const OTHER = '998912000001';
const MOD_KEYS = ['moderatedAt', 'moderatedBy', 'rejectReason', 'expiresAt', 'expiryWarnedAt', 'expiredAt', 'submittedAt', 'updatedBy', 'expiryWarnedFor'];

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-market-moderation-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const items = () => as(OWNER).collection('tv_shop_items');
  const item = (extra = {}) => ({
    ownerPhone: OWNER, title: 'Qo\'y', description: '', price: 100, photoUrls: [], clipIds: [],
    kind: 'product', status: 'active', viewCount: 0, ...extra,
  });
  const valueFor = (k) => (/At$/.test(k) || k === 'expiryWarnedFor' ? Timestamp.fromMillis(Date.now() + 86400000) : 'x');
  const seed = (fn) => testEnv.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

  await testEnv.clearFirestore();
  await seed(async (db) => {
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(OWNER).set({ role: 'user' });
    await db.collection('users').doc(OTHER).set({ role: 'user' });
    for (const st of ['active', 'pending', 'expired', 'rejected']) {
      await db.collection('tv_shop_items').doc(`s_${st}`).set(item({ status: st, expiresAt: Timestamp.fromMillis(1), moderatedBy: 'A' }));
    }
  });

  // ── tv_shop_items create ──
  await check('C1 эски APK шакли: status active ва pending — яратилади', async () => {
    await assertSucceeds(items().doc('c_a').set(item()));
    await assertSucceeds(items().doc('c_p').set(item({ status: 'pending' })));
  });
  await check('C2 модерация/муддат майдонлари билан яратиш — рад (ҳар бир майдон)', async () => {
    for (const k of MOD_KEYS) await assertFails(items().doc(`c_${k}`).set(item({ [k]: valueFor(k) })));
  });
  await check('C3 status expired/rejected/deleted билан яратиш — рад', async () => {
    for (const st of ['expired', 'rejected', 'deleted']) await assertFails(items().doc(`c_st_${st}`).set(item({ status: st })));
  });

  // ── tv_shop_items owner update ──
  await check('U1 эга контентни таҳрирлайди (active/expired/rejected/pending) — ўтади (pending ни сервер қўяди)', async () => {
    for (const st of ['active', 'pending', 'expired', 'rejected']) {
      await assertSucceeds(items().doc(`s_${st}`).update({ title: `Yangi ${st}`, price: 200 }));
    }
  });
  await check('U2 эга модерация майдонларини ўзгартира/ўчира олмайди', async () => {
    const { deleteField } = require('firebase/firestore');
    for (const k of MOD_KEYS) await assertFails(items().doc('s_active').update({ [k]: valueFor(k) }));
    await assertFails(items().doc('s_active').update({ expiresAt: deleteField() }));
    await assertFails(items().doc('s_active').update({ moderatedBy: deleteField() }));
  });
  await check('U3 эга ўзини active қила олмайди (expired/rejected/pending → active), pending ҳам қила олмайди', async () => {
    for (const st of ['pending', 'expired', 'rejected']) await assertFails(items().doc(`s_${st}`).update({ status: 'active' }));
    await assertFails(items().doc('s_expired').update({ status: 'pending' }));
  });
  await check('U4 эга истаган ҳолатдан deleted — ўтади; бегона — рад', async () => {
    await assertFails(as(OTHER).collection('tv_shop_items').doc('s_expired').update({ status: 'deleted' }));
    for (const st of ['pending', 'expired', 'rejected', 'active']) await assertSucceeds(items().doc(`s_${st}`).update({ status: 'deleted' }));
  });
  await check('U5 админ модерация майдонларини ёза олади (мавжуд isAdmin шохи)', async () => {
    await seed((db) => db.collection('tv_shop_items').doc('s_adm').set(item({ status: 'pending' })));
    await assertSucceeds(as(ADMIN).collection('tv_shop_items').doc('s_adm').update({ status: 'active', expiresAt: Timestamp.fromMillis(Date.now() + 1e9) }));
  });

  // ── wholesale_products owner update ──
  const wp = (extra = {}) => ({
    sellerId: OWNER, sellerCompanyName: 'G', title: 'Un 50 kg', titleLower: 'un 50 kg', description: 'Oliy nav un',
    priceTiers: [{ minQty: 1, price: 100 }], unit: 'qop', imageUrls: ['https://e.test/a.jpg'], status: 'active',
    views: 0, videoClipIds: [], market: 'wholesale', createdAt: Timestamp.fromMillis(1), ...extra,
  });
  await seed(async (db) => {
    await db.collection('wholesale_products').doc('w_active').set(wp());
    await db.collection('wholesale_products').doc('w_inactive').set(wp({ status: 'inactive' }));
    await db.collection('wholesale_products').doc('w_pending').set(wp({ status: 'pending' }));
  });
  const wcol = () => as(OWNER).collection('wholesale_products');
  await check('W1 active: контент ўзгариши + status ўзгармаса — РАД (ҳар бир контент майдони)', async () => {
    const patches = {
      title: 'Un 25 kg', description: 'Boshqa tavsif', imageUrls: ['https://e.test/b.jpg'],
      minOrderQty: 2, unit: 'kg', deliveryDays: 5, unitWeightG: 1000, unitDims: { l: 1, w: 1, h: 1 }, currency: 'USD',
    };
    for (const [k, v] of Object.entries(patches)) await assertFails(wcol().doc('w_active').update({ [k]: v }));
  });
  await check('W1b active: narx-faqat (priceTiers / packs) status o\'zgarmasa - O\'TADI (ega 2026-11-20)', async () => {
    await seed((db) => db.collection('wholesale_products').doc('w_price').set(wp()));
    await assertSucceeds(wcol().doc('w_price').update({ priceTiers: [{ minQty: 1, price: 90 }], updatedAt: serverTimestamp() }));
    await assertSucceeds(wcol().doc('w_price').update({ packs: [{ id: 'p1', label: '1', priceTiers: [{ minQty: 1, price: 80 }] }] }));
    await assertFails(wcol().doc('w_price').update({ priceTiers: [{ minQty: 1, price: 70 }], title: 'Yangi nom' }));
  });
  await check('W2 active: контент + status pending (жорий илова) — ўтади; контент + inactive — ўтади', async () => {
    await assertSucceeds(wcol().doc('w_active').update({ title: 'Un 25 kg', status: 'pending', updatedAt: serverTimestamp() }));
    await seed((db) => db.collection('wholesale_products').doc('w_active2').set(wp()));
    await assertSucceeds(wcol().doc('w_active2').update({ description: 'Yashirdim', status: 'inactive' }));
  });
  await check('W3 inactive қолиб контент таҳрири — ўтади; pending қолиб контент таҳрири — ўтади', async () => {
    await assertSucceeds(wcol().doc('w_inactive').update({ title: 'Un yangi' }));
    await assertSucceeds(wcol().doc('w_pending').update({ title: 'Un yangi 2' }));
  });
  await check('W4 контентсиз ўзгаришлар ўзгармади: active → inactive (яшириш), inactive → pending (қайта), updatedAt', async () => {
    await seed((db) => db.collection('wholesale_products').doc('w_a3').set(wp()));
    await assertSucceeds(wcol().doc('w_a3').update({ updatedAt: serverTimestamp() }));
    await assertSucceeds(wcol().doc('w_a3').update({ status: 'inactive' }));
    await assertSucceeds(wcol().doc('w_a3').update({ status: 'pending' }));
    await assertFails(wcol().doc('w_a3').update({ status: 'active' }));
  });

  await testEnv.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
