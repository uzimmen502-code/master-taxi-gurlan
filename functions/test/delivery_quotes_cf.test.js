/**
 * «Бозорлар» STAGE 11 (эга 2026-11-16) — катта маиший техника етказиш нархи СЎРОВИ (delivery_quotes.js):
 * ҲАҚИҚИЙ `functions/index.js` callable'лари `.run()` орқали, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-delivery-quotes \
 *     "node test/delivery_quotes_cf.test.js"
 *
 * Қулфланади: катта тўплам (соф); босқич OFF → MODULE_OFF; катта ЭМАС → DELIVERY_QUOTE_NOT_NEEDED;
 * катта товар оддий quote/place'да → DELIVERY_QUOTE_REQUIRED; сўров + идемпотентлик; рухсатлар
 * (бегона/мижоз жавоб бера олмайди, ўз сўровига курьер — QUOTE_SELF_RESPOND); нарх чегаралари;
 * рўйхат проекцияси (курьерга манзил йўқ); ПОЙГА (админ + 2 курьер → битта ғолиб, қолганлар
 * QUOTE_ALREADY_ANSWERED); тасдиқ → буюртма сўров нархи билан, сўров `used`, такрор → дубликат;
 * муддат ўтган → QUOTE_EXPIRED ва янги сўров.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18497';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-delivery-quotes';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.DIRECTIONS_API_KEY = '';
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0';
process.env.BUSINESS_ORDERS_TAXONOMY_CACHE_MS = '0';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* лойиҳа керак, берилган: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const bo = require('../business_orders');

const db = admin.firestore();

const SHOP = '998931200001';
const BUYER = '998932200001';
const STRANGER = '998934200001';
const ADMIN = '998935200001';
const COURIER_A = '998933200001';
const COURIER_B = '998933200002';
const ACC = { [COURIER_A]: 'accDQ00000000000A', [COURIER_B]: 'accDQ00000000000B' };

const S_LOC = { lat: 41.8406, lng: 60.3917 };
const C_LOC = { lat: 41.8586, lng: 60.3917 };
const TARIFF = { base: 6000, perKm: 1500, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 15, version: 3 };
const n3 = (s) => ({ uz_Cyrl: s, uz_Latn: s, ru: s });
const TAXONOMY = {
  version: 3,
  markets: {
    meat: { moduleId: 'meat_market', categories: [{ id: 'beef', names: n3('beef'), orderable: true }] },
    appliances: {
      moduleId: 'appliances_market',
      categories: ['fridges', 'washers', 'stoves', 'air_conditioners', 'vacuums'].map((id) => ({ id, names: n3(id), orderable: true })),
    },
  },
};

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const codeOf = (e) => (e.details && (e.details.code || e.details.reason)) || e.message;
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(codeOf(e), code, `код ${codeOf(e)} (${e.code}): ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const quote = async (id) => (await db.collection('delivery_quotes').doc(id).get()).data() || {};

const base = { ownerPhone: SHOP, kind: 'product', status: 'active', districtId: 'gurlan', priceUnit: 'piece' };
const ITEMS = {
  fridge: { ...base, price: 4500000, market: 'appliances', category: 'fridges', title: 'Artel muzlatkich' },
  washer: { ...base, price: 3000000, market: 'appliances', category: 'washers', title: 'Kir yuvish' },
  ac: { ...base, price: 5000000, market: 'appliances', category: 'air_conditioners', title: 'Konditsioner' },
  vacuum: { ...base, price: 900000, market: 'appliances', category: 'vacuums', title: 'Changyutgich' },
  meat: { ...base, price: 80000, priceUnit: 'kg', market: 'meat', category: 'beef', title: 'Go\'sht' },
};

async function reset() {
  await clearEmulator();
  await db.collection('server_config').doc('business_orders').set({ stage: 'public' });
  await db.collection('settings').doc('restaurant_delivery').set(TARIFF);
  await db.collection('taxonomy').doc('markets').set(TAXONOMY);
  for (const u of [SHOP, BUYER, STRANGER]) await db.collection('users').doc(u).set({ role: 'user', name: `U${u.slice(-4)}` });
  await db.collection('users').doc(ADMIN).set({ role: 'admin', name: 'Admin' });
  for (const c of [COURIER_A, COURIER_B]) {
    await db.collection('users').doc(c).set({ role: 'user', accountId: ACC[c] });
    await db.collection('provider_capabilities').doc(ACC[c]).set({
      identity: { accountId: ACC[c], primaryUid: c }, courier: { active: true }, status: { courier: 'approved' },
    });
  }
  await db.collection('tv_shops').doc(SHOP).set({
    ownerPhone: SHOP, name: 'Texnika uyi', pickupLat: S_LOC.lat, pickupLng: S_LOC.lng, pickupAddress: 'Gurlan bozor 7',
  });
  for (const [id, d] of Object.entries(ITEMS)) await db.collection('tv_shop_items').doc(id).set(d);
}

const request = (itemId, over = {}, who = BUYER) => call('requestDeliveryQuote', {
  itemId, qty: 1, ...C_LOC, address: 'Mijoz uyi, 3-podyezd', floor: 4, note: 'lift yo\'q', ...over,
}, who);

async function main() {
  await reset();

  await check('P1 isLargeDeliveryLine (соф): fridges/washers/stoves/air_conditioners — ҳа; vacuums/meat/бозорсиз — йўқ', async () => {
    for (const c of ['fridges', 'washers', 'stoves', 'air_conditioners']) assert.strictEqual(bo.isLargeDeliveryLine({ market: 'appliances', category: c }), true, c);
    assert.strictEqual(bo.isLargeDeliveryLine({ market: 'appliances', category: 'vacuums' }), false);
    assert.strictEqual(bo.isLargeDeliveryLine({ market: 'meat', category: 'beef' }), false);
    assert.strictEqual(bo.isLargeDeliveryLine({}), false);
    assert.strictEqual(bo.isLargeDeliveryLine({ market: 'toString', category: 'x' }), false);
    assert.ok(Object.isFrozen(bo.LARGE_DELIVERY_CATEGORIES.appliances));
  });

  await check('G1 босқич OFF → requestDeliveryQuote MODULE_OFF', async () => {
    const cfg = db.collection('server_config').doc('business_orders');
    await cfg.delete();
    await expectCode(request('fridge'), 'MODULE_OFF');
    await cfg.set({ stage: 'pilot', pilotDistrictIds: ['urganch'] });
    await expectCode(request('fridge'), 'MODULE_NOT_IN_PILOT');
    await cfg.set({ stage: 'public' });
  });

  await check('N1 катта ЭМАС (vacuums, meat) → DELIVERY_QUOTE_NOT_NEEDED; оддий quote ишлайди', async () => {
    await expectCode(request('vacuum'), 'DELIVERY_QUOTE_NOT_NEEDED');
    await expectCode(request('meat'), 'DELIVERY_QUOTE_NOT_NEEDED');
    assert.strictEqual((await call('quoteBusinessOrder', { items: [{ itemId: 'vacuum', qty: 1 }], ...C_LOC }, BUYER)).ok, true);
  });

  await check('N2 катта товар оддий quote/place (ёлғиз ёки аралаш) → DELIVERY_QUOTE_REQUIRED', async () => {
    await expectCode(call('quoteBusinessOrder', { items: [{ itemId: 'fridge', qty: 1 }], ...C_LOC }, BUYER), 'DELIVERY_QUOTE_REQUIRED');
    await expectCode(call('placeBusinessOrder', {
      idempotencyKey: 'dq_test_place_1', items: [{ itemId: 'vacuum', qty: 1 }, { itemId: 'washer', qty: 1 }], ...C_LOC, deliveryPaymentMethod: 'cash',
    }, BUYER), 'DELIVERY_QUOTE_REQUIRED');
  });

  await check('V1 киритиш: координатасиз / қават 61 / qty 0 → рад; пикап йўқ → SELLER_PICKUP_LOCATION_MISSING', async () => {
    await expectCode(call('requestDeliveryQuote', { itemId: 'fridge' }, BUYER), 'DELIVERY_ADDRESS_REQUIRED');
    await expectCode(request('fridge', { floor: 61 }), 'FLOOR_INVALID');
    await expectCode(request('fridge', { qty: 0 }), 'ITEM_INVALID');
    await expectCode(request('nope'), 'ITEM_NOT_FOUND');
    await db.collection('tv_shops').doc(SHOP).update({ pickupLat: admin.firestore.FieldValue.delete() });
    try {
      await expectCode(request('fridge'), 'SELLER_PICKUP_LOCATION_MISSING');
    } finally {
      await db.collection('tv_shops').doc(SHOP).update({ pickupLat: S_LOC.lat });
    }
    await expectCode(request('fridge', {}, SHOP), 'OWN_BUSINESS');
  });

  let qid = '';
  await check('R1 сўров: open ҳужжат (сервер майдонлари), такрор → ўша quoteId (duplicate)', async () => {
    const r = await request('fridge', { qty: 2 });
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.duplicate, false);
    assert.strictEqual(r.status, 'open');
    qid = r.quoteId;
    const q = await quote(qid);
    assert.strictEqual(q.buyerUid, BUYER);
    assert.strictEqual(q.sellerUid, SHOP);
    assert.strictEqual(q.sellerKind, 'shop');
    assert.strictEqual(q.qty, 2);
    assert.strictEqual(q.itemsTotal, 9000000);
    assert.strictEqual(q.floor, 4);
    assert.strictEqual(q.pickupAddress, 'Gurlan bozor 7');
    assert.strictEqual(q.priceUzs, null);
    assert.ok(q.expiresAt.toMillis() - Date.now() > 23 * 3600 * 1000);
    const r2 = await request('fridge');
    assert.strictEqual(r2.quoteId, qid);
    assert.strictEqual(r2.duplicate, true);
  });

  await check('A1 рухсат: бегона/мижоз жавоб ва рўйхат → QUOTE_RESPONDER_NOT_ALLOWED; нарх 0 / каср / 10M+ → PRICE_INVALID; жавобсиз тасдиқ → QUOTE_NOT_ANSWERED', async () => {
    await expectCode(call('respondDeliveryQuote', { quoteId: qid, priceUzs: 50000 }, STRANGER), 'QUOTE_RESPONDER_NOT_ALLOWED');
    await expectCode(call('respondDeliveryQuote', { quoteId: qid, priceUzs: 50000 }, BUYER), 'QUOTE_RESPONDER_NOT_ALLOWED');
    await expectCode(call('listOpenDeliveryQuotes', {}, BUYER), 'QUOTE_RESPONDER_NOT_ALLOWED');
    for (const p of [0, 50000.5, '50000', 10000001]) {
      await expectCode(call('respondDeliveryQuote', { quoteId: qid, priceUzs: p }, ADMIN), 'PRICE_INVALID');
    }
    await expectCode(call('respondDeliveryQuote', { quoteId: 'nope123', priceUzs: 50000 }, ADMIN), 'QUOTE_NOT_FOUND');
    await expectCode(call('acceptDeliveryQuote', { quoteId: qid }, BUYER), 'QUOTE_NOT_ANSWERED');
  });

  await check('L1 рўйхат: курьерга проекция (манзил/телефон ЙЎҚ), админга манзил + телефон охири', async () => {
    const c = await call('listOpenDeliveryQuotes', { lat: C_LOC.lat, lng: C_LOC.lng }, COURIER_A);
    assert.strictEqual(c.viewer, 'courier');
    const cq = c.quotes.find((x) => x.id === qid);
    assert.ok(cq, 'курьер кўради');
    assert.strictEqual(cq.address, undefined);
    assert.strictEqual(cq.buyerPhoneTail, undefined);
    assert.strictEqual(cq.floor, 4);
    assert.ok(cq.courierToPickupM > 0);
    const far = await call('listOpenDeliveryQuotes', { lat: 40.0, lng: 65.0 }, COURIER_A);
    assert.strictEqual(far.quotes.length, 0, 'радиусдан ташқари');
    const a = await call('listOpenDeliveryQuotes', {}, ADMIN);
    assert.strictEqual(a.viewer, 'admin');
    const aq = a.quotes.find((x) => x.id === qid);
    assert.strictEqual(aq.address, 'Mijoz uyi, 3-podyezd');
    assert.strictEqual(aq.buyerPhoneTail, BUYER.slice(-4));
  });

  await check('S1 курьер ўз сўровига жавоб бера олмайди (QUOTE_SELF_RESPOND) ва рўйхатда кўрмайди', async () => {
    const r = await request('ac', {}, COURIER_B);
    await expectCode(call('respondDeliveryQuote', { quoteId: r.quoteId, priceUzs: 70000 }, COURIER_B), 'QUOTE_SELF_RESPOND');
    const l = await call('listOpenDeliveryQuotes', {}, COURIER_B);
    assert.ok(!l.quotes.some((x) => x.id === r.quoteId));
  });

  await check('RACE админ + 2 курьер бир вақтда → битта ғолиб, қолганлар QUOTE_ALREADY_ANSWERED; ғолиб такрори идемпотент', async () => {
    const who = [ADMIN, COURIER_A, COURIER_B];
    const prices = [60000, 55000, 65000];
    const out = await Promise.allSettled(who.map((w, i) => call('respondDeliveryQuote', { quoteId: qid, priceUzs: prices[i] }, w)));
    const ok = out.filter((x) => x.status === 'fulfilled');
    const bad = out.filter((x) => x.status === 'rejected');
    assert.strictEqual(ok.length, 1, JSON.stringify(out.map((x) => x.status === 'rejected' ? codeOf(x.reason) : x.value)));
    for (const b of bad) assert.strictEqual(codeOf(b.reason), 'QUOTE_ALREADY_ANSWERED');
    const winIdx = out.findIndex((x) => x.status === 'fulfilled');
    const q = await quote(qid);
    assert.strictEqual(q.status, 'answered');
    assert.strictEqual(q.priceUzs, prices[winIdx]);
    assert.strictEqual(q.respondedBy, who[winIdx]);
    assert.strictEqual(q.responderRole, winIdx === 0 ? 'admin' : 'courier');
    const again = await call('respondDeliveryQuote', { quoteId: qid, priceUzs: 1000 }, who[winIdx]);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(again.priceUzs, prices[winIdx], 'нарх ўзгармайди');
    const audit = await db.collection('admin_audit').where('kind', '==', 'delivery_quote_respond').get();
    assert.strictEqual(audit.size, winIdx === 0 ? 1 : 0);
    const ev = await db.collection('delivery_quotes').doc(qid).collection('events').get();
    assert.strictEqual(ev.size, 2, 'open + answered');
  });

  await check('AU1 админ жавоби admin_audit га тушади', async () => {
    const r = await request('washer');
    await call('respondDeliveryQuote', { quoteId: r.quoteId, priceUzs: 40000 }, ADMIN);
    const audit = await db.collection('admin_audit').where('target', '==', `delivery_quotes/${r.quoteId}`).get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().actor, ADMIN);
    assert.strictEqual(audit.docs[0].data().detail.priceUzs, 40000);
  });

  await check('C1 тасдиқ: бегона → NOT_QUOTE_OWNER; мижоз → буюртма сўров нархи билан, сўров used; такрор → дубликат', async () => {
    const q0 = await quote(qid);
    await expectCode(call('acceptDeliveryQuote', { quoteId: qid }, STRANGER), 'NOT_QUOTE_OWNER');
    const r = await call('acceptDeliveryQuote', { quoteId: qid, deliveryPaymentMethod: 'cash', deliveryFee: 1 }, BUYER);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.deliveryFee, q0.priceUzs, 'клиент нархи эътиборсиз');
    const o = (await db.collection('orders').doc(r.orderId).get()).data();
    assert.strictEqual(o.type, 'business');
    assert.strictEqual(o.deliveryFee, q0.priceUzs);
    assert.strictEqual(o.deliveryFeeSource, 'delivery_quote');
    assert.strictEqual(o.deliveryQuoteId, qid);
    assert.strictEqual(o.deliveryTariffVersion, null);
    assert.strictEqual(o.itemsTotal, 9000000);
    assert.strictEqual(o.total, 9000000 + q0.priceUzs);
    assert.strictEqual(o.items[0].category, 'fridges');
    assert.strictEqual(o.floor, undefined);
    assert.strictEqual(o.address, 'Mijoz uyi, 3-podyezd');
    assert.strictEqual(o.businessStatus, 'placed');
    const q = await quote(qid);
    assert.strictEqual(q.status, 'used');
    assert.strictEqual(q.orderId, r.orderId);
    const r2 = await call('acceptDeliveryQuote', { quoteId: qid }, BUYER);
    assert.strictEqual(r2.orderId, r.orderId);
    assert.strictEqual(r2.duplicate, true);
    const all = await db.collection('orders').where('deliveryQuoteId', '==', qid).get();
    assert.strictEqual(all.size, 1);
    await expectCode(call('respondDeliveryQuote', { quoteId: qid, priceUzs: 50000 }, COURIER_B), 'QUOTE_ALREADY_ANSWERED');
    const nq = await request('fridge');
    assert.notStrictEqual(nq.quoteId, qid, 'used сўровдан кейин янги сўров');
  });

  await check('E1 муддат ўтган: жавоб → QUOTE_EXPIRED, тасдиқ → QUOTE_EXPIRED, рўйхатда йўқ, янги сўров яратилади', async () => {
    const r = await request('ac');
    const past = admin.firestore.Timestamp.fromMillis(Date.now() - 1000);
    await db.collection('delivery_quotes').doc(r.quoteId).update({ expiresAt: past });
    await expectCode(call('respondDeliveryQuote', { quoteId: r.quoteId, priceUzs: 50000 }, ADMIN), 'QUOTE_EXPIRED');
    await expectCode(call('acceptDeliveryQuote', { quoteId: r.quoteId }, BUYER), 'QUOTE_EXPIRED');
    const a = await call('listOpenDeliveryQuotes', {}, ADMIN);
    assert.ok(!a.quotes.some((x) => x.id === r.quoteId));
    const r2 = await request('ac');
    assert.notStrictEqual(r2.quoteId, r.quoteId);
    assert.strictEqual(r2.duplicate, false);
    // жавоб берилган, кейин муддат ўтган → тасдиқ рад
    await call('respondDeliveryQuote', { quoteId: r2.quoteId, priceUzs: 45000 }, COURIER_A);
    await db.collection('delivery_quotes').doc(r2.quoteId).update({ expiresAt: past });
    await expectCode(call('acceptDeliveryQuote', { quoteId: r2.quoteId }, BUYER), 'QUOTE_EXPIRED');
  });

  await check('G2 босқич тасдиқдан олдин OFF бўлса → MODULE_OFF (буюртма йўқ, сўров answered қолади)', async () => {
    const r = await request('washer', {}, STRANGER);
    await call('respondDeliveryQuote', { quoteId: r.quoteId, priceUzs: 30000 }, ADMIN);
    await db.collection('server_config').doc('business_orders').set({ stage: 'off' });
    try {
      await expectCode(call('acceptDeliveryQuote', { quoteId: r.quoteId }, STRANGER), 'MODULE_OFF');
      assert.strictEqual((await quote(r.quoteId)).status, 'answered');
    } finally {
      await db.collection('server_config').doc('business_orders').set({ stage: 'public' });
    }
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
