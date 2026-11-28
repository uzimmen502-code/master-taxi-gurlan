/**
 * «Бозорлар» 2a — модерация ва 30 кунлик муддат: ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-market-moderation \
 *     "node test/market_moderation_cf.test.js"
 *
 * Триггер (onShopItemModeration), adminModerateListing, renewMarketListing, marketListingsExpirySweep (+ эски
 * realtyExpirySweep ўчирмаслиги), marketListingsExpiryWarning, tools/migrate_market_expiry.js (dry-run/apply/rollback).
 */
'use strict';
const assert = require('assert');
const fs = require('fs');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-market-moderation';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const migrate = require('../tools/migrate_market_expiry');
const { resetAutoApproveCache } = require('../market_moderation');

const db = admin.firestore();
const FV = admin.firestore.FieldValue;
const TS = admin.firestore.Timestamp;
const DAY = 24 * 60 * 60 * 1000;
const ADMIN = '998915000001';
const OWNER = '998901112233';
const OTHER = '998912000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code, status) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    if (status) assert.strictEqual(e.code, status, `status ${e.code}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const items = db.collection('tv_shop_items');
const get = async (col, id) => (await db.collection(col).doc(id).get()).data();
const news = async (uid) => (await db.collection('admin_news').where('targetUserId', '==', uid).get()).docs.map((d) => d.data());
const audits = async () => (await db.collection('admin_audit').where('kind', '==', 'listing_moderation').get()).docs.map((d) => d.data());

/** Ҳақиқий ёзув + триггерни ўша before/after снимоклари билан чақириш. */
async function writeAndTrigger(id, writeFn) {
  const ref = items.doc(id);
  const before = await ref.get();
  await writeFn(ref);
  const after = await ref.get();
  await fns.onShopItemModeration.run({ before, after }, { params: { itemId: id } });
  return { before, after, data: (await ref.get()).data() };
}
const item = (extra = {}) => ({ ownerPhone: OWNER, title: 'Qo\'y', description: 'd', price: 100, photoUrls: ['p'], clipIds: [], kind: 'product', status: 'active', viewCount: 0, ...extra });
const moderate = (data, who = ADMIN) => fns.adminModerateListing.run(data, ctxOf(who));
const renew = (data, who = OWNER) => fns.renewMarketListing.run(data, ctxOf(who));

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(OWNER).set({ role: 'user', appLang: 'uz_Latn', realtyOwnerKey: 'key_owner' });
  await db.collection('users').doc(OTHER).set({ role: 'user', realtyOwnerKey: 'key_other' });

  // ── Триггер ──
  await check('T1 create active → pending (+submittedAt); такрорий триггер — ўзгармайди', async () => {
    const r = await writeAndTrigger('t1', (ref) => ref.set(item()));
    assert.strictEqual(r.data.status, 'pending');
    assert.ok(r.data.submittedAt, 'submittedAt');
    assert.strictEqual(r.data.moderationReason, 'new');
    const snap = await items.doc('t1').get();
    await fns.onShopItemModeration.run({ before: r.after, after: snap }, { params: { itemId: 't1' } });
    const again = (await items.doc('t1').get());
    assert.strictEqual(again.updateTime.toMillis(), snap.updateTime.toMillis(), 'ўз ёзувидан кейин loop йўқ');
    await fns.onShopItemModeration.run({ before: r.before, after: r.after }, { params: { itemId: 't1' } });
    assert.strictEqual((await items.doc('t1').get()).updateTime.toMillis(), snap.updateTime.toMillis(), 'create қайта етказилса — идемпотент');
  });
  await check('T2 create pending → submittedAt қўйилади; ownerPhoneсиз (social merge) — тегилмайди', async () => {
    const r = await writeAndTrigger('t2', (ref) => ref.set(item({ status: 'pending' })));
    assert.strictEqual(r.data.status, 'pending'); assert.ok(r.data.submittedAt);
    const s = await writeAndTrigger('t2b', (ref) => ref.set({ socialPostedAt: FV.serverTimestamp() }, { merge: true }));
    assert.strictEqual(s.data.status, undefined);
  });
  await check('T3 эга active контентини таҳрирлади → pending (rejectReason олинади); контент бўлмаган ўзгариш — active қолади', async () => {
    await items.doc('t3').set(item({ status: 'active', rejectReason: 'eski', expiresAt: TS.fromMillis(Date.now() + 10 * DAY) }));
    const n = await writeAndTrigger('t3', (ref) => ref.update({ clipIds: ['c1'] }));
    assert.strictEqual(n.data.status, 'active');
    // Narx-faqat (ega 2026-11-20) - active qoladi.
    assert.strictEqual((await writeAndTrigger('t3', (ref) => ref.update({ price: 200, priceUnit: 'kg' }))).data.status, 'active');
    const r = await writeAndTrigger('t3', (ref) => ref.update({ title: 'Qo\'y 2' }));
    assert.strictEqual(r.data.status, 'pending');
    assert.strictEqual(r.data.moderationReason, 'owner_edit');
    assert.strictEqual(r.data.rejectReason, undefined);
  });
  await check('T3b expired контент таҳрири → pending; rejected таҳрири — rejected қолади', async () => {
    await items.doc('t3e').set(item({ status: 'expired' }));
    assert.strictEqual((await writeAndTrigger('t3e', (ref) => ref.update({ attrs: { a: 1 } }))).data.status, 'pending');
    await items.doc('t3r').set(item({ status: 'rejected' }));
    assert.strictEqual((await writeAndTrigger('t3r', (ref) => ref.update({ title: 'yangi' }))).data.status, 'rejected');
  });
  await check('T4 эга ўчирди (status deleted) ва ҳужжат ўчирилди — триггер ҳеч нарса ёзмайди', async () => {
    await items.doc('t4').set(item({ status: 'active' }));
    const r = await writeAndTrigger('t4', (ref) => ref.update({ status: 'deleted', title: 'x' }));
    assert.strictEqual(r.data.status, 'deleted');
    const before = await items.doc('t4').get();
    await items.doc('t4').delete();
    const after = await items.doc('t4').get();
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 't4' } });
    assert.strictEqual((await items.doc('t4').get()).exists, false);
  });
  await check('T5 админ CF таҳрири (updatedBy + admin_audit ўша вақт) — pending ҚИЛИНМАЙДИ', async () => {
    await items.doc('t5').set(item({ status: 'active', businessId: 'b1' }));
    const r = await writeAndTrigger('t5', async (ref) => {
      const b = db.batch();
      b.update(ref, { title: 'Admin tahriri', updatedAt: FV.serverTimestamp(), updatedBy: ADMIN });
      b.set(db.collection('admin_audit').doc(), { kind: 'business_product_update', actor: ADMIN, target: 't5', at: FV.serverTimestamp() });
      await b.commit();
    });
    assert.strictEqual(r.data.status, 'active');
    // Сохта: эга updatedAt'ни ўзгартирса, лекин audit йўқ → pending.
    const s = await writeAndTrigger('t5', (ref) => ref.update({ title: 'Egasi', updatedAt: FV.serverTimestamp() }));
    assert.strictEqual(s.data.status, 'pending');
  });
  await check('T6 админ тўғридан-тўғри pending → active (клип модерацияси) → expiresAt +30 кун қўйилади', async () => {
    await items.doc('t6').set(item({ status: 'pending', submittedAt: TS.now() }));
    const r = await writeAndTrigger('t6', (ref) => ref.update({ status: 'active' }));
    const exp = r.data.expiresAt.toMillis();
    assert.ok(Math.abs(exp - (Date.now() + 30 * DAY)) < 60000, `expiresAt ${new Date(exp).toISOString()}`);
  });

  // ── Авто-тасдиқ: settings/app.shopItemAutoApprove (эга 2026-11-19) ──
  const setAuto = async (v) => {
    if (v === undefined) await db.collection('settings').doc('app').set({ marketAutoApprove: true });
    else await db.collection('settings').doc('app').set({ shopItemAutoApprove: v, marketAutoApprove: true });
    resetAutoApproveCache();
  };
  await check('A1 калит true: create → active (+submittedAt, moderatedAt, moderatedBy auto, reason auto, +30 кун); loop/такрор йўқ', async () => {
    await setAuto(true);
    const r = await writeAndTrigger('a1', (ref) => ref.set(item()));
    assert.strictEqual(r.data.status, 'active');
    assert.ok(r.data.submittedAt && r.data.moderatedAt);
    assert.strictEqual(r.data.moderatedBy, 'auto'); assert.strictEqual(r.data.moderationReason, 'auto');
    assert.ok(Math.abs(r.data.expiresAt.toMillis() - (Date.now() + 30 * DAY)) < 60000);
    const snap = await items.doc('a1').get();
    await fns.onShopItemModeration.run({ before: r.after, after: snap }, { params: { itemId: 'a1' } });
    assert.strictEqual((await items.doc('a1').get()).updateTime.toMillis(), snap.updateTime.toMillis(), 'ўз ёзувидан кейин loop йўқ');
    await fns.onShopItemModeration.run({ before: r.before, after: r.after }, { params: { itemId: 'a1' } });
    assert.strictEqual((await items.doc('a1').get()).updateTime.toMillis(), snap.updateTime.toMillis(), 'create қайта етказилса — идемпотент');
    const p = await writeAndTrigger('a1p', (ref) => ref.set(item({ status: 'pending' })));
    assert.strictEqual(p.data.status, 'active', 'pending яратилса ҳам');
    assert.strictEqual((await audits()).filter((x) => ['a1', 'a1p'].includes(x.id)).length, 0, 'admin_audit ёзилмайди');
  });
  await check('A2 калит true: active таҳрири — active қолади, expiresAt ўзгармайди, триггер ёзмайди', async () => {
    const exp = TS.fromMillis(Date.now() + 10 * DAY);
    await items.doc('a2').set(item({ status: 'active', expiresAt: exp, moderatedAt: TS.fromMillis(Date.now() - DAY) }));
    const r = await writeAndTrigger('a2', (ref) => ref.update({ title: 'Boshqa' }));
    assert.strictEqual(r.data.status, 'active'); assert.strictEqual(r.data.expiresAt.toMillis(), exp.toMillis());
    assert.strictEqual((await items.doc('a2').get()).updateTime.toMillis(), r.after.updateTime.toMillis(), 'ёзув йўқ');
  });
  await check('A3 калит true: expired таҳрири → active (+30 кун); renew → active; қайта триггер — ёзув йўқ', async () => {
    await items.doc('a3').set(item({ status: 'expired', expiresAtPrev: TS.fromMillis(Date.now() - DAY) }));
    const r = await writeAndTrigger('a3', (ref) => ref.update({ title: 'Yangi' }));
    assert.strictEqual(r.data.status, 'active'); assert.strictEqual(r.data.moderationReason, 'auto');
    assert.strictEqual(r.data.expiresAtPrev, undefined);
    assert.ok(Math.abs(r.data.expiresAt.toMillis() - (Date.now() + 30 * DAY)) < 60000);
    await items.doc('a3r').set(item({ status: 'expired' }));
    const before = await items.doc('a3r').get();
    await renew({ collection: 'tv_shop_items', id: 'a3r' });
    const after = await items.doc('a3r').get();
    assert.strictEqual(after.data().status, 'pending');
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 'a3r' } });
    const d = await items.doc('a3r').get();
    assert.strictEqual(d.data().status, 'active'); assert.strictEqual(d.data().moderatedBy, 'auto');
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 'a3r' } });
    assert.strictEqual((await items.doc('a3r').get()).updateTime.toMillis(), d.updateTime.toMillis(), 'renew қайта етказилса — идемпотент');
  });
  await check('A4 калит false / йўқ (marketAutoApprove true бўлса ҳам) — қўлда: create → pending, renew → pending қолади', async () => {
    for (const [i, v] of [[0, false], [1, undefined], [2, 'true']]) {
      await setAuto(v);
      const r = await writeAndTrigger(`a4_${i}`, (ref) => ref.set(item()));
      assert.strictEqual(r.data.status, 'pending', `калит ${v}`);
      assert.strictEqual(r.data.moderationReason, 'new');
    }
    await items.doc('a4r').set(item({ status: 'expired' }));
    const before = await items.doc('a4r').get();
    await renew({ collection: 'tv_shop_items', id: 'a4r' });
    const after = await items.doc('a4r').get();
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 'a4r' } });
    const d = await items.doc('a4r').get();
    assert.strictEqual(d.data().status, 'pending'); assert.strictEqual(d.updateTime.toMillis(), after.updateTime.toMillis());
  });
  await check('A5 кеш: калит ёқилгач reset қилинмаса — 60 с ичида эски қиймат (қўлда) ишлатилади', async () => {
    await setAuto(false);
    await writeAndTrigger('a5_warm', (ref) => ref.set(item()));
    await db.collection('settings').doc('app').set({ shopItemAutoApprove: true }); // reset йўқ
    const r = await writeAndTrigger('a5', (ref) => ref.set(item()));
    assert.strictEqual(r.data.status, 'pending', 'кешдаги false');
    resetAutoApproveCache();
    assert.strictEqual((await writeAndTrigger('a5b', (ref) => ref.set(item()))).data.status, 'active');
    await db.collection('settings').doc('app').delete();
    resetAutoApproveCache();
  });

  // ── adminModerateListing ──
  await check('M1 оддий фойдаланувчи / токенсиз — рад', async () => {
    await items.doc('m1').set(item({ status: 'pending' }));
    await assert.rejects(moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'approve' }, OWNER), (e) => e.code === 'permission-denied');
    await assert.rejects(fns.adminModerateListing.run({ collection: 'tv_shop_items', id: 'm1', decision: 'approve' }, {}), (e) => e.code === 'unauthenticated');
    assert.strictEqual((await get('tv_shop_items', 'm1')).status, 'pending');
  });
  await check('M2 нотўғри аргументлар: COLLECTION_INVALID / DECISION_INVALID / REASON_REQUIRED / LISTING_NOT_FOUND', async () => {
    await expectCode(moderate({ collection: 'users', id: 'm1', decision: 'approve' }), 'COLLECTION_INVALID', 'invalid-argument');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'maybe' }), 'DECISION_INVALID', 'invalid-argument');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'reject' }), 'REASON_REQUIRED', 'invalid-argument');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'reject', reason: '   ' }), 'REASON_REQUIRED');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'reject', reason: 'x'.repeat(301) }), 'REASON_REQUIRED');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'nope', decision: 'approve' }), 'LISTING_NOT_FOUND', 'not-found');
    await db.collection('ads').doc('job1').set({ type: 'job', status: 'pending' });
    await expectCode(moderate({ collection: 'ads', id: 'job1', decision: 'approve' }), 'COLLECTION_INVALID');
    assert.strictEqual((await audits()).length, 0);
  });
  await check('M3 tv approve: active + expiresAt +30 + audit + эгага хабар (uz_Latn); триггер loop қилмайди; қайта → LISTING_NOT_PENDING', async () => {
    const before = await items.doc('m1').get();
    const r = await moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'approve' });
    assert.strictEqual(r.status, 'active');
    const after = await items.doc('m1').get();
    const d = after.data();
    assert.strictEqual(d.status, 'active'); assert.strictEqual(d.moderatedBy, ADMIN);
    assert.ok(Math.abs(d.expiresAt.toMillis() - (Date.now() + 30 * DAY)) < 60000);
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 'm1' } });
    assert.strictEqual((await items.doc('m1').get()).updateTime.toMillis(), after.updateTime.toMillis(), 'loop йўқ');
    const a = (await audits()).filter((x) => x.id === 'm1');
    assert.strictEqual(a.length, 1); assert.strictEqual(a[0].decision, 'approve'); assert.strictEqual(a[0].actor, ADMIN); assert.strictEqual(a[0].collection, 'tv_shop_items');
    const n = await news(OWNER);
    assert.ok(n.some((x) => x.title.includes('tasdiqlandi')), JSON.stringify(n.map((x) => x.title)));
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'm1', decision: 'approve' }), 'LISTING_NOT_PENDING', 'failed-precondition');
  });
  await check('M4 tv reject: rejected + rejectReason + audit (reason) + хабар сабаб билан', async () => {
    await items.doc('m4').set(item({ status: 'pending', title: 'Sigir' }));
    await moderate({ collection: 'tv_shop_items', id: 'm4', decision: 'reject', reason: 'Rasm noto\'g\'ri' });
    const d = await get('tv_shop_items', 'm4');
    assert.strictEqual(d.status, 'rejected'); assert.strictEqual(d.rejectReason, 'Rasm noto\'g\'ri');
    assert.ok((await audits()).some((x) => x.id === 'm4' && x.reason === 'Rasm noto\'g\'ri'));
    assert.ok((await news(OWNER)).some((x) => x.body === '«Sigir»: Rasm noto\'g\'ri'));
  });
  await check('M5 wholesale approve — active, expiresAt ЙЎҚ; reject — inactive + adminNote', async () => {
    await db.collection('wholesale_products').doc('w1').set({ sellerId: OWNER, title: 'Un', status: 'pending' });
    await moderate({ collection: 'wholesale_products', id: 'w1', decision: 'approve' });
    const w = await get('wholesale_products', 'w1');
    assert.strictEqual(w.status, 'active'); assert.strictEqual(w.expiresAt, undefined); assert.ok(w.publishedAt);
    await db.collection('wholesale_products').doc('w2').set({ sellerId: OWNER, title: 'Shakar', status: 'pending' });
    await moderate({ collection: 'wholesale_products', id: 'w2', decision: 'reject', reason: 'Narx yo\'q' });
    const w2 = await get('wholesale_products', 'w2');
    assert.strictEqual(w2.status, 'inactive'); assert.strictEqual(w2.adminNote, 'Narx yo\'q');
  });
  await check('M6 realty approve — expiresAt +30 + хабар private/detail.ownerId га; reject — blocked', async () => {
    const r1 = db.collection('realty_listings').doc('r1');
    await r1.set({ ownerKey: 'key_owner', title: 'Uy', status: 'pending', tier: 'plain', expiryWarnedAt: TS.now() });
    await r1.collection('private').doc('detail').set({ ownerId: OWNER });
    await moderate({ collection: 'realty_listings', id: 'r1', decision: 'approve' });
    const d = await get('realty_listings', 'r1');
    assert.strictEqual(d.status, 'active'); assert.strictEqual(d.expiryWarnedAt, undefined);
    assert.ok(Math.abs(d.expiresAt.toMillis() - (Date.now() + 30 * DAY)) < 60000);
    assert.ok((await news(OWNER)).some((x) => x.body.includes('«Uy»')));
    await db.collection('realty_listings').doc('r2').set({ ownerKey: 'key_owner', title: 'Uy2', status: 'pending' });
    await moderate({ collection: 'realty_listings', id: 'r2', decision: 'reject', reason: 'Manzil' });
    assert.strictEqual((await get('realty_listings', 'r2')).status, 'blocked');
  });
  await check('M7 ads approve — active, expiresAt +30, adminRejected false; бу ердан push ЙЎҚ (onAdUpdate юборади)', async () => {
    await db.collection('ads').doc('a1').set({ type: 'cheap_product', ownerId: OTHER, title: 'Pomidor', status: 'pending' });
    const n0 = (await news(OTHER)).length;
    await moderate({ collection: 'ads', id: 'a1', decision: 'approve' });
    const a = await get('ads', 'a1');
    assert.strictEqual(a.status, 'active'); assert.strictEqual(a.adminRejected, false);
    assert.ok(Math.abs(a.expiresAt.toMillis() - (Date.now() + 30 * DAY)) < 60000);
    assert.strictEqual((await news(OTHER)).length, n0);
    await db.collection('ads').doc('a2').set({ type: 'cheap_product', ownerId: OTHER, title: 'Piyoz', status: 'pending' });
    await moderate({ collection: 'ads', id: 'a2', decision: 'reject', reason: 'Takror' });
    const a2 = await get('ads', 'a2');
    assert.strictEqual(a2.status, 'inactive'); assert.strictEqual(a2.adminRejected, true); assert.strictEqual(a2.adminNote, 'Takror');
  });

  // ── «Админ тузатиб тасдиқлайди» (эга 2026-11-15) ──
  const fixItem = (extra = {}) => item({
    status: 'rejected', title: 'Sigir yomon', description: 'eski', price: 500, priceUnit: '', market: 'livestock', category: 'cow',
    photoUrls: ['p1', 'p2', 'p3'], photoUrl: 'p1', rejectReason: 'Rasm', rejectedAt: TS.now(), moderatedAt: TS.fromMillis(Date.now() - 60000), ...extra,
  });
  await check('E1 rejected + edits → active: контент + статус бир ёзувда, photoUrl янгиланади, rejectReason олинади, audit edits, хабар', async () => {
    await items.doc('e_fix').set(fixItem());
    const n0 = (await news(OWNER)).length;
    const before = await items.doc('e_fix').get();
    const r = await moderate({
      collection: 'tv_shop_items', id: 'e_fix', decision: 'approve',
      edits: { title: 'Sigir', description: 'x'.repeat(400), price: 7000000, priceUnit: 'ton', category: 'heifer', photoUrls: ['p2', 'p3'], imported: true, attrs: { age: 3 } },
    });
    assert.strictEqual(r.status, 'active');
    assert.deepStrictEqual(r.editedFields.sort(), ['attrs', 'category', 'description', 'imported', 'photoUrl', 'photoUrls', 'price', 'priceUnit', 'title']);
    const after = await items.doc('e_fix').get();
    const d = after.data();
    assert.strictEqual(d.status, 'active'); assert.strictEqual(d.title, 'Sigir'); assert.strictEqual(d.price, 7000000);
    assert.strictEqual(d.priceUnit, 'ton'); assert.strictEqual(d.category, 'heifer'); assert.strictEqual(d.imported, true);
    assert.deepStrictEqual(d.photoUrls, ['p2', 'p3']); assert.strictEqual(d.photoUrl, 'p2');
    assert.strictEqual(d.rejectReason, undefined); assert.strictEqual(d.moderatedBy, ADMIN);
    assert.ok(Math.abs(d.expiresAt.toMillis() - (Date.now() + 30 * DAY)) < 60000);
    // Триггер: таҳрир + тасдиқ ёзуви эга таҳрири деб олинмайди (pending'га қайтмайди, loop йўқ).
    await fns.onShopItemModeration.run({ before, after }, { params: { itemId: 'e_fix' } });
    const again = await items.doc('e_fix').get();
    assert.strictEqual(again.updateTime.toMillis(), after.updateTime.toMillis(), 'триггер ёзмади');
    assert.strictEqual(again.data().status, 'active');
    const a = (await audits()).filter((x) => x.id === 'e_fix');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].previousStatus, 'rejected'); assert.strictEqual(a[0].nextStatus, 'active'); assert.strictEqual(a[0].actor, ADMIN);
    const t = a[0].edits.find((x) => x.field === 'title');
    assert.deepStrictEqual(t, { field: 'title', before: 'Sigir yomon', after: 'Sigir' });
    const ds = a[0].edits.find((x) => x.field === 'description');
    assert.strictEqual(ds.after.length, 301, 'audit 300 белгигача қисқартирилган');
    assert.deepStrictEqual(a[0].edits.find((x) => x.field === 'photoUrls'), { field: 'photoUrls', before: ['p1', 'p2', 'p3'], after: ['p2', 'p3'] });
    assert.ok(a[0].editedFields.includes('priceUnit'));
    const n = await news(OWNER);
    assert.strictEqual(n.length - n0, 1);
    assert.ok(n.some((x) => x.body.includes('«Sigir»')), 'хабарда тузатилган сарлавҳа');
  });
  await check('E2 photoUrls: янги URL / такрор — INVALID_EDITS (ҳужжат ва аудит ўзгармайди); қисм-тўплам — ўтади', async () => {
    await items.doc('e_ph').set(fixItem());
    const t0 = (await items.doc('e_ph').get()).updateTime.toMillis();
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_ph', decision: 'approve', edits: { photoUrls: ['p1', 'https://evil/x.jpg'] } }), 'INVALID_EDITS', 'invalid-argument');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_ph', decision: 'approve', edits: { photoUrls: ['p1', 'p1'] } }), 'INVALID_EDITS', 'invalid-argument');
    assert.strictEqual((await items.doc('e_ph').get()).updateTime.toMillis(), t0);
    assert.strictEqual((await audits()).filter((x) => x.id === 'e_ph').length, 0);
    await moderate({ collection: 'tv_shop_items', id: 'e_ph', decision: 'approve', edits: { photoUrls: ['p3'] } });
    const d = await get('tv_shop_items', 'e_ph');
    assert.deepStrictEqual(d.photoUrls, ['p3']); assert.strictEqual(d.photoUrl, 'p3'); assert.strictEqual(d.status, 'active');
  });
  await check('E3 нотўғри: priceUnit / номаълум калит / reject+edits / ads+edits / category marketсиз — рад, ёзув йўқ', async () => {
    await items.doc('e_bad').set(fixItem({ status: 'pending' }));
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_bad', decision: 'approve', edits: { priceUnit: 'tonna' } }), 'INVALID_EDITS', 'invalid-argument');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_bad', decision: 'approve', edits: { status: 'active' } }), 'INVALID_EDITS');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_bad', decision: 'approve', edits: { ownerPhone: OTHER } }), 'INVALID_EDITS');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_bad', decision: 'approve', edits: { price: 1.5 } }), 'INVALID_EDITS');
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_bad', decision: 'reject', reason: 'x', edits: { title: 'y' } }), 'EDITS_REQUIRE_APPROVE');
    await db.collection('ads').doc('e_ad').set({ type: 'cheap_product', ownerId: OTHER, title: 'Olma', status: 'pending' });
    await expectCode(moderate({ collection: 'ads', id: 'e_ad', decision: 'approve', edits: { title: 'y' } }), 'EDITS_NOT_SUPPORTED');
    await items.doc('e_nomk').set(item({ status: 'pending' }));
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_nomk', decision: 'approve', edits: { category: 'cow' } }), 'INVALID_EDITS');
    assert.strictEqual((await get('tv_shop_items', 'e_bad')).status, 'pending');
    assert.strictEqual((await get('ads', 'e_ad')).status, 'pending');
    assert.strictEqual((await audits()).filter((x) => ['e_bad', 'e_ad', 'e_nomk'].includes(x.id)).length, 0);
  });
  await check('E4 оддий фойдаланувчи (эга ҳам) edits билан — permission-denied; rejected ўзгармайди', async () => {
    await items.doc('e_own').set(fixItem());
    await assert.rejects(moderate({ collection: 'tv_shop_items', id: 'e_own', decision: 'approve', edits: { title: 'Men' } }, OWNER), (e) => e.code === 'permission-denied');
    await assert.rejects(fns.adminModerateListing.run({ collection: 'tv_shop_items', id: 'e_own', decision: 'approve', edits: { title: 'Men' } }, {}), (e) => e.code === 'unauthenticated');
    const d = await get('tv_shop_items', 'e_own');
    assert.strictEqual(d.status, 'rejected'); assert.strictEqual(d.title, 'Sigir yomon');
  });
  await check('E5 rejected edits сиз approve — мумкин; rejected reject — LISTING_NOT_PENDING; wholesale inactive approve — LISTING_NOT_PENDING', async () => {
    await items.doc('e_plain').set(fixItem());
    await expectCode(moderate({ collection: 'tv_shop_items', id: 'e_plain', decision: 'reject', reason: 'yana' }), 'LISTING_NOT_PENDING', 'failed-precondition');
    const r = await moderate({ collection: 'tv_shop_items', id: 'e_plain', decision: 'approve' });
    assert.strictEqual(r.status, 'active'); assert.deepStrictEqual(r.editedFields, []);
    const a = (await audits()).find((x) => x.id === 'e_plain');
    assert.strictEqual(a.edits, undefined); assert.strictEqual(a.previousStatus, 'rejected');
    await db.collection('wholesale_products').doc('e_w').set({ sellerId: OWNER, title: 'Un', status: 'inactive' });
    await expectCode(moderate({ collection: 'wholesale_products', id: 'e_w', decision: 'approve' }), 'LISTING_NOT_PENDING');
    // Кейин эга контентни ўзгартирса — одатдагидек pending (админ таҳрири белгиси кейинги ёзувга «юқмайди»).
    const s = await writeAndTrigger('e_fix', (ref) => ref.update({ title: 'Egasi o\'zgartirdi' }));
    assert.strictEqual(s.data.status, 'pending');
  });

  // ── renewMarketListing ──
  await check('R1 renew: бегона — NOT_OWNER; эга expired → pending; такрор → changed:false; active → LISTING_NOT_EXPIRED', async () => {
    await items.doc('e1').set(item({ status: 'expired' }));
    await expectCode(renew({ collection: 'tv_shop_items', id: 'e1' }, OTHER), 'NOT_OWNER', 'permission-denied');
    await assert.rejects(fns.renewMarketListing.run({ collection: 'tv_shop_items', id: 'e1' }, {}), (e) => e.code === 'unauthenticated');
    const r = await renew({ collection: 'tv_shop_items', id: 'e1' });
    assert.deepStrictEqual(r, { ok: true, status: 'pending', changed: true });
    const d = await get('tv_shop_items', 'e1');
    assert.strictEqual(d.status, 'pending'); assert.ok(d.submittedAt); assert.strictEqual(d.moderationReason, 'renew');
    assert.deepStrictEqual(await renew({ collection: 'tv_shop_items', id: 'e1' }), { ok: true, status: 'pending', changed: false });
    await expectCode(renew({ collection: 'tv_shop_items', id: 'm1' }), 'LISTING_NOT_EXPIRED', 'failed-precondition');
    await expectCode(renew({ collection: 'wholesale_products', id: 'w1' }), 'COLLECTION_INVALID');
    await expectCode(renew({ collection: 'tv_shop_items', id: 'nope' }), 'LISTING_NOT_FOUND');
  });
  await check('R2 realty renew — ownerKey орқали; бегона калит — рад', async () => {
    await db.collection('realty_listings').doc('re1').set({ ownerKey: 'key_owner', title: 'Uy', status: 'expired' });
    await expectCode(renew({ collection: 'realty_listings', id: 're1' }, OTHER), 'NOT_OWNER');
    await renew({ collection: 'realty_listings', id: 're1' });
    assert.strictEqual((await get('realty_listings', 're1')).status, 'pending');
  });
  // F-1 (эга 2026-11-28): эски «Аралаш» эълони (`ads`) қайта жойлаштирилмайди — MARKET_AD_RETIRED, ёзув йўқ.
  await check('R3 ads renew — F-1: муддати ўзи тугаган inactive ҳам MARKET_AD_RETIRED (3 тил), inactive қолади; бегона — NOT_OWNER', async () => {
    await db.collection('ads').doc('ae1').set({ type: 'cheap_product', ownerId: OWNER, status: 'inactive', autoExpiredAt: TS.now() });
    await assert.rejects(renew({ collection: 'ads', id: 'ae1' }), (e) => {
      assert.strictEqual(e.code, 'failed-precondition');
      assert.strictEqual(e.details.code, 'MARKET_AD_RETIRED');
      for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(e.details.messages[l], l);
      return true;
    });
    assert.strictEqual((await get('ads', 'ae1')).status, 'inactive');
    await db.collection('ads').doc('ae2').set({ type: 'cheap_product', ownerId: OWNER, status: 'inactive', autoExpiredAt: TS.now(), adminRejected: true });
    await expectCode(renew({ collection: 'ads', id: 'ae2' }), 'MARKET_AD_RETIRED');
    await expectCode(renew({ collection: 'ads', id: 'ae1' }, OTHER), 'NOT_OWNER');
  });

  // ── Супуриш ──
  await check('S1 sweep: tv/realty active ўтган → expired (expiresAt олинади, expiresAtPrev); келажак/wholesale тегилмайди; realty pending — фақат expiresAt олинади', async () => {
    const past = TS.fromMillis(Date.now() - 1000);
    const future = TS.fromMillis(Date.now() + 5 * DAY);
    await items.doc('s1').set(item({ status: 'active', title: 'Eski', expiresAt: past }));
    await items.doc('s2').set(item({ status: 'active', expiresAt: future }));
    await items.doc('s3').set(item({ status: 'deleted', expiresAt: past }));
    await db.collection('wholesale_products').doc('ws').set({ sellerId: OWNER, status: 'active', expiresAt: past });
    const rs = db.collection('realty_listings');
    await rs.doc('rs1').set({ ownerKey: 'key_owner', title: 'Uy eski', status: 'active', expiresAt: past });
    await rs.doc('rs1').collection('private').doc('detail').set({ ownerId: OWNER });
    await rs.doc('rs2').set({ ownerKey: 'key_owner', status: 'pending', expiresAt: past });
    await rs.doc('rs3').set({ ownerKey: 'key_owner', status: 'active', expiresAt: TS.fromMillis(Date.now() + 10 * 60 * 1000) });
    await rs.doc('rs4').set({ ownerKey: 'key_owner', status: 'active', expiresAt: TS.fromMillis(Date.now() + 60 * 60 * 1000) });
    const n0 = (await news(OWNER)).length;
    await fns.marketListingsExpirySweep.run({}, {});
    const s1 = await get('tv_shop_items', 's1');
    assert.strictEqual(s1.status, 'expired'); assert.strictEqual(s1.expiresAt, undefined); assert.strictEqual(s1.expiresAtPrev.toMillis(), past.toMillis()); assert.ok(s1.expiredAt);
    assert.strictEqual((await get('tv_shop_items', 's2')).status, 'active');
    const s3 = await get('tv_shop_items', 's3'); assert.strictEqual(s3.status, 'deleted'); assert.strictEqual(s3.expiresAt, undefined);
    assert.strictEqual((await get('wholesale_products', 'ws')).status, 'active');
    assert.strictEqual((await get('realty_listings', 'rs1')).status, 'expired');
    const r2 = await get('realty_listings', 'rs2'); assert.strictEqual(r2.status, 'pending'); assert.strictEqual(r2.expiresAt, undefined);
    assert.strictEqual((await get('realty_listings', 'rs3')).status, 'expired', '15 дақиқалик ҳимоя');
    assert.strictEqual((await get('realty_listings', 'rs4')).status, 'active');
    const n = await news(OWNER);
    // s1 (ownerPhone) + rs1 (private/detail.ownerId); rs3 да private йўқ — хабарсиз.
    assert.strictEqual(n.length - n0, 2, `хабарлар: ${n.length - n0}`);
  });
  await check('S2 sweep қайта — идемпотент (ёзув ва хабар йўқ); эски realtyExpirySweep муддати тугаганларни ЎЧИРМАЙДИ', async () => {
    const t0 = (await items.doc('s1').get()).updateTime.toMillis();
    const n0 = (await news(OWNER)).length;
    await fns.marketListingsExpirySweep.run({}, {});
    assert.strictEqual((await items.doc('s1').get()).updateTime.toMillis(), t0);
    assert.strictEqual((await news(OWNER)).length, n0);
    await fns.realtyExpirySweep.run({}, {});
    for (const id of ['rs1', 'rs2', 'rs3']) assert.ok((await db.collection('realty_listings').doc(id).get()).exists, `${id} ўчмаган`);
  });

  // ── Огоҳлантириш ──
  await check('W1 warning: tv + ads(cheap_product) 24 соат ичида → хабар + expiryWarnedFor; қайта — йўқ; job тури ва realty — йўқ', async () => {
    const soon = TS.fromMillis(Date.now() + 12 * 60 * 60 * 1000);
    await items.doc('w_tv').set(item({ status: 'active', title: 'Tez', expiresAt: soon }));
    await db.collection('ads').doc('w_ad').set({ type: 'cheap_product', ownerId: OTHER, title: 'Olma', status: 'active', expiresAt: soon });
    await db.collection('ads').doc('w_job').set({ type: 'job', authorPhone: OTHER, title: 'Ish', status: 'active', expiresAt: soon });
    await db.collection('realty_listings').doc('w_r').set({ ownerKey: 'key_owner', status: 'active', expiresAt: soon });
    const o0 = (await news(OWNER)).length; const x0 = (await news(OTHER)).length;
    await fns.marketListingsExpiryWarning.run({}, {});
    assert.strictEqual((await news(OWNER)).length - o0, 1);
    assert.strictEqual((await news(OTHER)).length - x0, 1);
    assert.strictEqual((await get('tv_shop_items', 'w_tv')).expiryWarnedFor.toMillis(), soon.toMillis());
    assert.strictEqual((await get('ads', 'w_job')).expiryWarnedFor, undefined);
    assert.strictEqual((await get('realty_listings', 'w_r')).expiryWarnedFor, undefined);
    await fns.marketListingsExpiryWarning.run({}, {});
    assert.strictEqual((await news(OWNER)).length - o0, 1, 'такрор хабар йўқ');
  });

  // ── Миграция ──
  await check('G1 migrate: dry-run ёзмайди; apply — фақат active + expiresAt йўқлар (+backup); rollback — қайтаради', async () => {
    await clearEmulator();
    const keep = TS.fromMillis(Date.now() + 3 * DAY);
    await items.doc('g1').set(item({ status: 'active' }));
    await items.doc('g2').set(item({ status: 'active', expiresAt: keep }));
    await items.doc('g3').set(item({ status: 'pending' }));
    await db.collection('realty_listings').doc('g4').set({ status: 'active' });
    await db.collection('ads').doc('g5').set({ type: 'cheap_product', status: 'active' });
    await db.collection('ads').doc('g6').set({ type: 'job', status: 'active' });
    await db.collection('wholesale_products').doc('g7').set({ status: 'active' });
    const project = process.env.GCLOUD_PROJECT;
    const dry = await migrate.main(['--project', project]);
    assert.strictEqual(dry.planned, 3);
    assert.strictEqual((await get('tv_shop_items', 'g1')).expiresAt, undefined);
    const res = await migrate.main(['--project', project, '--apply']);
    assert.strictEqual(res.done, 3); assert.strictEqual(res.verified, 3);
    const g1 = (await get('tv_shop_items', 'g1')).expiresAt.toMillis();
    assert.ok(Math.abs(g1 - (Date.now() + 30 * DAY)) < 120000);
    assert.strictEqual((await get('tv_shop_items', 'g2')).expiresAt.toMillis(), keep.toMillis(), 'мавжуд expiresAt ўзгармайди');
    assert.strictEqual((await get('tv_shop_items', 'g3')).expiresAt, undefined);
    assert.ok((await get('realty_listings', 'g4')).expiresAt); assert.ok((await get('ads', 'g5')).expiresAt);
    assert.strictEqual((await get('ads', 'g6')).expiresAt, undefined); assert.strictEqual((await get('wholesale_products', 'g7')).expiresAt, undefined);
    const bk = JSON.parse(fs.readFileSync(res.backup, 'utf8'));
    assert.strictEqual(bk.docs.length, 3);
    // Иккинчи apply — ҳеч нарса (идемпотент).
    assert.strictEqual((await migrate.main(['--project', project, '--apply'])).planned, 0);
    // Rollback: g4 ни модерация ўзгартирган деб фараз — тегилмайди.
    await db.collection('realty_listings').doc('g4').update({ expiresAt: TS.fromMillis(Date.now() + 9 * DAY) });
    const rb = await migrate.main(['--project', project, '--rollback', res.backup, '--apply']);
    assert.strictEqual(rb.done, 2);
    assert.strictEqual((await get('tv_shop_items', 'g1')).expiresAt, undefined);
    assert.ok((await get('realty_listings', 'g4')).expiresAt, 'кейин ўзгарган — қолди');
    fs.unlinkSync(res.backup);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
