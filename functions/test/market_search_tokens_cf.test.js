/**
 * Сервер қидируви токенлари (2026-11-16): ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-search-tokens \
 *     "node test/market_search_tokens_cf.test.js"
 *
 * onShopItemSearchTokens / onRealtySearchTokens: create/update/no-loop/idempotent; onShopItemModeration'га таъсир йўқ;
 * tools/backfill_search_tokens.js (dry-run ёзмайди, --apply фақат searchTokens, backup, қайта ишга тушса — 0).
 */
'use strict';
const assert = require('assert');
const fs = require('fs');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-search-tokens';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const tok = require('../market_search_tokens');
const backfill = require('../tools/backfill_search_tokens');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;
const OWNER = '998901112233';
const DAY = 24 * 60 * 60 * 1000;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}

/** Ёзув → триггер (ўша before/after). */
async function writeAndRun(fnName, col, id, writeFn) {
  const ref = db.collection(col).doc(id);
  const before = await ref.get();
  await writeFn(ref);
  const after = await ref.get();
  await fns[fnName].run({ before, after }, { params: { docId: id, itemId: id } });
  const now = await ref.get();
  return { before, after, now, data: now.data() };
}
const shop = (id, w) => writeAndRun('onShopItemSearchTokens', 'tv_shop_items', id, w);
const realty = (id, w) => writeAndRun('onRealtySearchTokens', 'realty_listings', id, w);
const item = (extra = {}) => ({ ownerPhone: OWNER, title: 'Sigir', description: 'Sog\'lom', price: 100, photoUrls: ['p'], clipIds: [], kind: 'product', status: 'active', viewCount: 0, market: 'livestock', ...extra });
const listing = (extra = {}) => ({ ownerKey: 'k1', ownerName: 'Akmal', title: 'Hovli', text: 'Katta uy', addressText: 'Navoiy 12', status: 'active', ...extra });

async function main() {
  await clearEmulator();

  await check('S1 tv_shop_items create → searchTokens (фақат шу майдон қўшилади)', async () => {
    const r = await shop('s1', (ref) => ref.set(item()));
    assert.deepStrictEqual(r.data.searchTokens, tok.shopItemTokens(item()));
    assert.ok(r.data.searchTokens.includes('sigir') && r.data.searchTokens.includes('сигир'));
    const keys = Object.keys(r.data).sort();
    assert.deepStrictEqual(keys, [...Object.keys(item()), 'searchTokens'].sort());
  });
  await check('S2 ўз ёзувидан кейин триггер — ёзмайди (no-loop); create қайта етказилса — идемпотент', async () => {
    const ref = db.collection('tv_shop_items').doc('s1');
    const snap = await ref.get();
    const prev = await shop('s1', async () => {}); // before == after (ўз ёзуви ҳолати)
    assert.strictEqual(prev.now.updateTime.toMillis(), snap.updateTime.toMillis());
    const empty = await db.collection('tv_shop_items').doc('nope').get();
    await fns.onShopItemSearchTokens.run({ before: empty, after: snap }, { params: { docId: 's1' } });
    assert.strictEqual((await ref.get()).updateTime.toMillis(), snap.updateTime.toMillis());
  });
  await check('S3 title/description таҳрири → янгиланади; бошқа майдон (price) → ёзув йўқ', async () => {
    const p = await shop('s1', (ref) => ref.update({ price: 500 }));
    assert.strictEqual(p.now.updateTime.toMillis(), p.after.updateTime.toMillis(), 'price — ёзилмади');
    const r = await shop('s1', (ref) => ref.update({ title: 'Buqa' }));
    assert.ok(r.data.searchTokens.includes('buqa') && !r.data.searchTokens.includes('sigir'));
  });
  await check('S4 эга searchTokens ни бузса (admin SDK симуляцияси) → тикланади; ҳужжат ўчирилса — ҳеч нарса', async () => {
    const r = await shop('s1', (ref) => ref.update({ searchTokens: ['spam'] }));
    assert.deepStrictEqual(r.data.searchTokens, tok.shopItemTokens(r.data));
    const before = await db.collection('tv_shop_items').doc('s1').get();
    await db.collection('tv_shop_items').doc('s1').delete();
    const after = await db.collection('tv_shop_items').doc('s1').get();
    await fns.onShopItemSearchTokens.run({ before, after }, { params: { docId: 's1' } });
    assert.strictEqual((await db.collection('tv_shop_items').doc('s1').get()).exists, false);
  });
  await check('S5 эскирган снимок: жорий ҳужжатдан ҳисобланади (орада келган таҳрир ютмайди)', async () => {
    const ref = db.collection('tv_shop_items').doc('s5');
    const before = await ref.get();
    await ref.set(item({ title: 'Echki' }));
    const after = await ref.get();
    await ref.update({ title: 'Qoʻy' });
    await fns.onShopItemSearchTokens.run({ before, after }, { params: { docId: 's5' } });
    assert.deepStrictEqual((await ref.get()).data().searchTokens, tok.shopItemTokens({ title: 'Qoʻy', description: 'Sog\'lom' }));
  });
  await check('S6 onShopItemModeration токен ёзувини эга таҳрири деб ҚАБУЛ ҚИЛМАЙДИ (active қолади)', async () => {
    const ref = db.collection('tv_shop_items').doc('s6');
    await ref.set(item({ status: 'active', submittedAt: TS.now(), expiresAt: TS.fromMillis(Date.now() + 10 * DAY) }));
    const before = await ref.get();
    await ref.update({ searchTokens: tok.shopItemTokens(item()) });
    const after = await ref.get();
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 's6' } });
    const d = (await ref.get()).data();
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.moderationReason, undefined);
    assert.strictEqual((await ref.get()).updateTime.toMillis(), after.updateTime.toMillis(), 'модерация ҳеч нарса ёзмади');
  });
  await check('S7 модерация ёзуви (status pending) → токен триггери ёзмайди', async () => {
    const ref = db.collection('tv_shop_items').doc('s7');
    await ref.set(item({ searchTokens: tok.shopItemTokens(item()) }));
    const r = await shop('s7', (x) => x.update({ status: 'pending', submittedAt: TS.now(), moderationReason: 'new' }));
    assert.strictEqual(r.now.updateTime.toMillis(), r.after.updateTime.toMillis());
  });

  await check('R1 realty create → токенлар title+text; ownerName/addressText йўқ', async () => {
    const r = await realty('r1', (ref) => ref.set(listing()));
    assert.deepStrictEqual(r.data.searchTokens, tok.realtyTokens(listing()));
    for (const x of ['akmal', 'navoiy']) assert.ok(!r.data.searchTokens.includes(x), x);
    assert.strictEqual(r.data.status, 'active');
  });
  await check('R2 updateRealtyListing шакли (searchTokens: delete) → қайта ёзилади; кейин — no-loop', async () => {
    const r = await realty('r1', (ref) => ref.update({ title: 'Kvartira', searchTokens: admin.firestore.FieldValue.delete() }));
    assert.ok(r.data.searchTokens.includes('kvartira'));
    const again = await realty('r1', async () => {});
    assert.strictEqual(again.now.updateTime.toMillis(), r.now.updateTime.toMillis());
  });
  await check('R3 realty status/narx ўзгариши → ёзув йўқ; ўчириш → ҳеч нарса', async () => {
    const r = await realty('r1', (ref) => ref.update({ status: 'blocked', priceText: '100' }));
    assert.strictEqual(r.now.updateTime.toMillis(), r.after.updateTime.toMillis());
    const before = await db.collection('realty_listings').doc('r1').get();
    await db.collection('realty_listings').doc('r1').delete();
    const after = await db.collection('realty_listings').doc('r1').get();
    await fns.onRealtySearchTokens.run({ before, after }, { params: { docId: 'r1' } });
    assert.strictEqual((await db.collection('realty_listings').doc('r1').get()).exists, false);
  });

  // ── Backfill ──
  await check('B1 backfill: dry-run ёзмайди; --apply фақат йўқ/фарқли; backup; қайта — 0; бошқа майдонлар тегилмайди', async () => {
    await clearEmulator();
    const items = db.collection('tv_shop_items');
    await items.doc('b1').set(item({ title: 'Ot' }));
    await items.doc('b2').set(item({ title: 'Tuya', searchTokens: tok.shopItemTokens({ title: 'Tuya', description: 'Sog\'lom' }) }));
    await items.doc('b3').set(item({ title: 'Eshak', searchTokens: ['eski'], status: 'expired' }));
    await db.collection('realty_listings').doc('b4').set(listing());
    const t0 = (await items.doc('b2').get()).updateTime.toMillis();
    const dry = await backfill.main(['--project', process.env.GCLOUD_PROJECT, '--collection', 'all']);
    assert.strictEqual(dry.planned, 3);
    assert.strictEqual(dry.done, 0);
    assert.strictEqual((await items.doc('b1').get()).data().searchTokens, undefined, 'dry-run ёзмади');
    const ap = await backfill.main(['--project', process.env.GCLOUD_PROJECT, '--collection', 'all', '--apply']);
    assert.strictEqual(ap.done, 3);
    assert.ok(fs.existsSync(ap.backup));
    const bk = JSON.parse(fs.readFileSync(ap.backup, 'utf8'));
    assert.deepStrictEqual(bk.docs.map((x) => x.id).sort(), ['b1', 'b3', 'b4']);
    assert.deepStrictEqual(bk.docs.find((x) => x.id === 'b3').searchTokens, ['eski']);
    assert.deepStrictEqual((await items.doc('b1').get()).data().searchTokens, tok.shopItemTokens({ title: 'Ot', description: 'Sog\'lom' }));
    assert.strictEqual((await items.doc('b3').get()).data().status, 'expired');
    assert.ok((await db.collection('realty_listings').doc('b4').get()).data().searchTokens.includes('hovli'));
    assert.strictEqual((await items.doc('b2').get()).updateTime.toMillis(), t0, 'тенг — тегилмади');
    const again = await backfill.main(['--project', process.env.GCLOUD_PROJECT, '--collection', 'all', '--apply']);
    assert.strictEqual(again.planned, 0);
    fs.unlinkSync(ap.backup);
  });
  await check('B2 backfill: --project шарт; нотўғри --collection — хато', async () => {
    await assert.rejects(backfill.main(['--collection', 'all']), /--project/);
    await assert.rejects(backfill.main(['--project', 'demo-x', '--collection', 'ads']), /--collection/);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
