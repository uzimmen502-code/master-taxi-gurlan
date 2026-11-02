/**
 * «МЕНИНГ БИЗНЕСИМ» — маҳсулот буюртмаси AVA курьери билан (эга 2026-11-03): ҲАҚИҚИЙ `functions/index.js`
 * callable'лари `.run()` орқали, Firestore Emulator, ҳақиқий ledger.
 *
 *   firebase emulators:exec --only firestore --project demo-biz-order \
 *     "node test/business_orders_cf.test.js"
 *
 * Қулфланади: босқич (OFF/INTERNAL/PILOT/PUBLIC), тариф йўқ → TARIFF_NOT_CONFIGURED, AVA улуши > 0 → рад,
 * нарх фақат каталогдан, хизмат/қатъий бўлмаган нарх/бегона/фаол бўлмаган маҳсулот рад, ўз объекти ва
 * онлайн объект рад, идемпотент жойлаш (кетма-кет ва параллел), фақат сотувчи қабул қилади, нотўғри ўтиш,
 * эски callable'лар бизнес буюртмасини кўрмайди/рад этади, иккита курьер → битта ғолиб, олиб кетиш коди,
 * ҳамён етказиш ҳақи (калит идемпотент, Σdr == Σcr), ҳамён етмаса нақд, муддат ўтса рад, мижоз тасдиғи
 * (received), «етказилмади» (delivery_failed.js: мижоз тасдиғи, сотувчи қарори, жадвал бошқа модулни
 * тозаламайди).
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18397';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-biz-order';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.DIRECTIONS_API_KEY = ''; // Directions чақирилмайди → тўғри чизиқ × йўл коэффициенти
process.env.CUSTOMER_CONFIRM_CACHE_MS = '0';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* лойиҳа керак, берилган: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index');
const admin = require('firebase-admin');
const ledger = require('../settlement_ledger');
const tariffMod = require('../restaurant_delivery_tariff');
const bo = require('../business_orders');

const db = admin.firestore();
const TS = admin.firestore.Timestamp;

const SELLER = '998931000001';
const BUYER = '998932000001';
const BUYER2 = '998932000002';
const STRANGER = '998934000001';
const ADMIN = '998935000001';
const COURIER_A = '998933000001';
const COURIER_B = '998933000002';
const ACC = { [COURIER_A]: 'accBIZ00000000000A', [COURIER_B]: 'accBIZ00000000000B' };

const B_LOC = { lat: 41.8406, lng: 60.3917 }; // Гурлан
const C_LOC = { lat: 41.8586, lng: 60.3917 }; // ~2 км шимолда
const TARIFF = { base: 6000, perKm: 1500, nightCoef: 1.5, nightStart: 23, nightEnd: 6, roadFactor: 1.3, maxKm: 15, version: 3 };

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code, httpsCode) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && (e.details.code || e.details.reason)) || e.message;
    assert.strictEqual(got, code, `код ${got} (${e.code}): ${e.message}`);
    if (httpsCode) assert.strictEqual(e.code, httpsCode);
    return true;
  });
}

async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function topUp(uid, amount, key) {
  await ledger.postEntry(db, {
    idempotencyKey: `topup:${uid}:${key}`, kind: 'test_topup',
    legs: [{ account: 'admin_clearing', dr: amount }, { account: ledger.passengerCreditAccount(uid), cr: amount }],
  });
}
const pcBal = async (uid) => {
  const s = await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid)).get();
  return s.exists ? Number(s.data().balance || 0) : 0;
};
const order = async (id) => (await db.collection('orders').doc(id).get()).data() || {};
const eventsOf = async (id) => (await db.collection('orders').doc(id).collection('order_events').orderBy('at').get()).docs.map((d) => d.data());
const secret = async (id) => (await db.collection('orders').doc(id).collection('private').doc('secrets').get()).data() || {};
async function journalBalanced() {
  const s = await db.collection(ledger.COL_JOURNAL).get();
  for (const d of s.docs) {
    const legs = d.data().legs || [];
    const dr = legs.reduce((a, l) => a + (l.dr || 0), 0);
    const cr = legs.reduce((a, l) => a + (l.cr || 0), 0);
    assert.strictEqual(dr, cr, `journal ${d.id} Σdr ${dr} != Σcr ${cr}`);
  }
  return s.size;
}
async function seedCourier(phone) {
  await db.collection('users').doc(phone).set({ role: 'user', accountId: ACC[phone], bonusBalance: 0 });
  await db.collection('provider_capabilities').doc(ACC[phone]).set({
    identity: { accountId: ACC[phone], primaryUid: phone },
    courier: { active: true }, status: { courier: 'approved' },
  });
}
function expectedFee(from, to, t = TARIFF) {
  const straight = tariffMod.haversineMeters(from.lat, from.lng, to.lat, to.lng);
  const m = Math.round((straight * 1300) / 1000);
  const prices = tariffMod.resolveDeliveryPrices(t, tariffMod.resolveRegionKey(from.lat, from.lng));
  const night = tariffMod.isNightAt(new Date(), prices.nightStartH, prices.nightEndH);
  return tariffMod.computeDeliveryFee({ distanceMeters: m, prices, night }).fee;
}
let keySeq = 0;
const key = () => `biz_test_${Date.now()}_${keySeq += 1}`;

const ITEMS = {
  p1: { businessId: 'biz1', ownerPhone: SELLER, kind: 'product', price: 20000, status: 'active', title: 'Kitob' },
  p2: { businessId: 'biz1', ownerPhone: SELLER, kind: 'product', price: 5000, priceUnit: 'kg', status: 'active', title: 'Olma' },
  p3: { businessId: 'biz1', ownerPhone: SELLER, price: 1000, status: 'active', title: 'Eski hujjat (kind yo\'q)' },
  svc: { businessId: 'biz1', ownerPhone: SELLER, kind: 'service', price: 30000, status: 'active', title: 'Ta\'mirlash' },
  pFrom: { businessId: 'biz1', ownerPhone: SELLER, kind: 'product', price: 9000, priceUnit: 'from', status: 'active', title: 'dan' },
  pHour: { businessId: 'biz1', ownerPhone: SELLER, kind: 'product', price: 9000, priceUnit: 'hour', status: 'active', title: 'soat' },
  pZero: { businessId: 'biz1', ownerPhone: SELLER, kind: 'product', price: 0, status: 'active', title: 'kelishiladi' },
  pPending: { businessId: 'biz1', ownerPhone: SELLER, kind: 'product', price: 7000, status: 'pending', title: 'kutilmoqda' },
  pOther: { businessId: 'biz2', ownerPhone: SELLER, kind: 'product', price: 7000, status: 'active', title: 'boshqa obyekt' },
  pForged: { businessId: 'biz1', ownerPhone: STRANGER, kind: 'product', price: 100, status: 'active', title: 'begona ega' },
  pOnline: { businessId: 'bizOnline', ownerPhone: SELLER, kind: 'product', price: 7000, status: 'active', title: 'onlayn' },
  pOwn: { businessId: 'bizBuyer', ownerPhone: BUYER, kind: 'product', price: 7000, status: 'active', title: 'o\'ziniki' },
};

async function reset() {
  await clearEmulator();
  await db.collection('server_config').doc('business_orders').set({ stage: 'public' });
  await db.collection('settings').doc('business_delivery').set(TARIFF);
  for (const u of [SELLER, BUYER, BUYER2, STRANGER]) {
    await db.collection('users').doc(u).set({ role: 'user', name: `U${u.slice(-4)}`, bonusBalance: 0 });
  }
  await db.collection('users').doc(ADMIN).set({ role: 'admin', bonusBalance: 0 });
  await seedCourier(COURIER_A);
  await seedCourier(COURIER_B);
  await topUp(BUYER, 100000, 'b');
  for (const c of [COURIER_A, COURIER_B]) {
    await db.collection('restaurant_courier_prefs').doc(c).set({ buyoutEnabled: true, buyoutLimit: 500000 });
  }
  await db.collection('businesses').doc('biz1').set({
    ownerId: SELLER, name: 'Gurlan kitob', category: 'retail', address: 'Gurlan markaz', ...B_LOC,
    regionId: 'xorazm', districtId: 'gurlan', status: 'active',
  });
  await db.collection('businesses').doc('biz2').set({ ownerId: SELLER, name: 'Ikkinchi', ...B_LOC, status: 'active', regionId: 'xorazm', districtId: 'gurlan' });
  await db.collection('businesses').doc('bizOnline').set({ ownerId: SELLER, name: 'Onlayn', online: true, status: 'active', regionId: '', districtId: '' });
  await db.collection('businesses').doc('bizBuyer').set({ ownerId: BUYER, name: 'Xaridor do\'koni', ...B_LOC, status: 'active', regionId: 'xorazm', districtId: 'gurlan' });
  for (const [id, d] of Object.entries(ITEMS)) await db.collection('tv_shop_items').doc(id).set(d);
}

const place = (who, over = {}) => call('placeBusinessOrder', {
  idempotencyKey: key(), businessId: 'biz1', items: [{ itemId: 'p1', qty: 2 }, { itemId: 'p2', qty: 3 }],
  address: 'Mijoz uyi', ...C_LOC, deliveryPaymentMethod: 'wallet', ...over,
}, who);

async function toReadyClaimed(over = {}) {
  const r = await place(BUYER, over);
  await call('businessAcceptOrder', { orderId: r.orderId }, SELLER);
  await call('businessMarkReady', { orderId: r.orderId }, SELLER);
  await call('courierClaimBusinessOrder', { orderId: r.orderId }, COURIER_A);
  return r;
}
async function toArrived(over = {}) {
  const r = await toReadyClaimed(over);
  const code = (await secret(r.orderId)).pickupCode;
  await call('courierPickupBusinessOrder', { orderId: r.orderId, pickupCode: code }, COURIER_A);
  await call('courierArriveBusinessOrder', { orderId: r.orderId }, COURIER_A);
  return r;
}

async function main() {
  await reset();
  const fee = expectedFee(B_LOC, C_LOC);

  // ── 1. Соф қисм ─────────────────────────────────────────────────────
  await check('U1 parseConfig/accessOf: ҳужжат йўқ → off; internal → тестер; pilot → туман; public → ҳамма', async () => {
    const canon = (v) => { const d = String(v).replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; };
    assert.strictEqual(bo.parseConfig(null, canon).stage, 'off');
    assert.strictEqual(bo.parseConfig({ stage: 'PUBLIC' }, canon).stage, 'off', 'нотўғри қиймат → off');
    const c = bo.parseConfig({ stage: 'pilot', testerIds: ['931000009', 'x'], pilotDistrictIds: ['gurlan', '../x'] }, canon);
    assert.deepStrictEqual(c.testerIds, ['998931000009']);
    assert.deepStrictEqual(c.pilotDistrictIds, ['gurlan']);
    assert.strictEqual(c.acceptTimeoutMin, bo.ACCEPT_TIMEOUT_MIN_DEFAULT);
    assert.strictEqual(bo.accessOf(c, BUYER, 'gurlan').allowed, true);
    assert.strictEqual(bo.accessOf(c, BUYER, 'urganch').reason, 'MODULE_NOT_IN_PILOT');
    assert.strictEqual(bo.accessOf(c, '998931000009', 'urganch').allowed, true);
    assert.strictEqual(bo.accessOf({ ...c, stage: 'internal' }, BUYER, 'gurlan').reason, 'MODULE_INTERNAL_ONLY');
    assert.strictEqual(bo.accessOf({ ...c, stage: 'off' }, '998931000009', 'gurlan').reason, 'MODULE_OFF');
  });
  await check('U2 resolveAvaFee: йўқ → 0; 0 → 0; > 0 → AVA_FEE_NOT_SUPPORTED; ғалат → AVA_FEE_CONFIG_INVALID', async () => {
    assert.deepStrictEqual(bo.resolveAvaFee({ version: 4 }), { ok: true, rateBps: 0, source: 'default', settingsVersion: 4 });
    assert.strictEqual(bo.resolveAvaFee({ avaFeeBps: 0 }).rateBps, 0);
    assert.strictEqual(bo.resolveAvaFee({ avaFeeBps: 200 }).code, 'AVA_FEE_NOT_SUPPORTED');
    assert.strictEqual(bo.resolveAvaFee({ avaFeeBps: '0' }).code, 'AVA_FEE_CONFIG_INVALID');
    assert.strictEqual(bo.resolveAvaFee({ avaFeeBps: 1.5 }).code, 'AVA_FEE_CONFIG_INVALID');
  });
  await check('U4 хабар матнлари: ҳар бизнес калити уч тилда, ўринбосарлар тўлади, uz_Latn лотинда, ички атама йўқ', async () => {
    const i18n = require('../notif_i18n');
    const keys = Object.keys(i18n.MESSAGES).filter((k) => k.startsWith('business_'));
    assert.ok(keys.length >= 14, `калитлар: ${keys.length}`);
    const params = { amount: '55 000', min: 15, name: 'Gurlan kitob', km: '1.2', fee: '9 000', buyout: '55 000' };
    for (const k of keys) {
      assert.deepStrictEqual(Object.keys(i18n.MESSAGES[k]).sort(), [...i18n.LANGS].sort(), k);
      for (const lang of i18n.LANGS) {
        const m = i18n.render(k, lang, params);
        assert.ok(m.title.length > 3 && m.body.length > 5, `${k}/${lang}`);
        assert.ok(!/\{\w+\}/.test(`${m.title} ${m.body}`), `${k}/${lang} ўринбосар`);
        assert.ok(!/\b(LEG|ZONE|settlement|escrow|ledger)\b/i.test(`${m.title} ${m.body}`), `${k}/${lang} ички атама`);
      }
      assert.ok(!/[а-яёўқғҳ]/i.test(JSON.stringify(i18n.render(k, 'uz_Latn', params))), `${k}: uz_Latn лотин`);
      assert.ok(/[а-яё]/i.test(i18n.render(k, 'uz_Cyrl', params).title), `${k}: uz_Cyrl кирилл`);
    }
  });
  await check('U3 ҳолат жадвали: placed→delivered йўқ, picked→delivered йўқ (аввал arrived), терминаллардан чиқиш йўқ', async () => {
    assert.strictEqual(bo.canTransition('placed', 'delivered'), false);
    assert.strictEqual(bo.canTransition('picked', 'delivered'), false);
    assert.strictEqual(bo.canTransition('arrived', 'delivered'), true);
    for (const f of bo.FINAL) for (const t of Object.values(bo.BS)) assert.strictEqual(bo.canTransition(f, t), false, `${f}→${t}`);
    assert.deepStrictEqual(bo.statusFields('ready'), { businessStatus: 'ready', status: 'ready', fulfillmentStatus: 'confirmed' });
  });

  // ── 2. Босқич, тариф, AVA улуши ─────────────────────────────────────
  await check('F1 босқич: ҳужжат йўқ → MODULE_OFF (quote ҳам, place ҳам); internal → фақат тестер; pilot → объект тумани; getBusinessOrdersAccess', async () => {
    const cfg = db.collection('server_config').doc('business_orders');
    await cfg.delete();
    await expectCode(place(BUYER), 'MODULE_OFF', 'failed-precondition');
    await expectCode(call('quoteBusinessOrder', { businessId: 'biz1', items: [{ itemId: 'p1', qty: 1 }], ...C_LOC }, BUYER), 'MODULE_OFF');
    assert.deepStrictEqual(await call('getBusinessOrdersAccess', {}, BUYER), { allowed: false, stage: 'off', reason: 'MODULE_OFF' });
    await cfg.set({ stage: 'internal', testerIds: [] });
    await expectCode(place(BUYER), 'MODULE_INTERNAL_ONLY');
    await cfg.set({ stage: 'internal', testerIds: [BUYER] });
    assert.strictEqual((await call('quoteBusinessOrder', { businessId: 'biz1', items: [{ itemId: 'p1', qty: 1 }], ...C_LOC }, BUYER)).itemsTotal, 20000);
    await cfg.set({ stage: 'pilot', testerIds: [], pilotDistrictIds: ['urganch'] });
    await expectCode(place(BUYER), 'MODULE_NOT_IN_PILOT');
    assert.strictEqual((await call('getBusinessOrdersAccess', { businessId: 'biz1' }, BUYER)).allowed, false);
    await cfg.set({ stage: 'pilot', testerIds: [], pilotDistrictIds: ['gurlan'] });
    assert.strictEqual((await call('getBusinessOrdersAccess', { businessId: 'biz1' }, BUYER)).allowed, true);
    await cfg.set({ stage: 'public' });
  });
  await check('F2 тариф ҳужжати йўқ → TARIFF_NOT_CONFIGURED; base йўқ → TARIFF_NOT_CONFIGURED', async () => {
    const t = db.collection('settings').doc('business_delivery');
    await t.delete();
    await expectCode(call('quoteBusinessOrder', { businessId: 'biz1', items: [{ itemId: 'p1', qty: 1 }], ...C_LOC }, BUYER), 'TARIFF_NOT_CONFIGURED', 'failed-precondition');
    await expectCode(place(BUYER), 'TARIFF_NOT_CONFIGURED');
    await t.set({ perKm: 1000, version: 1 });
    await expectCode(place(BUYER), 'TARIFF_NOT_CONFIGURED');
    // Ресторан тарифи бор бўлса ҳам бизнесга ишлатилмайди (алоҳида версияланган ҳужжат).
    await db.collection('settings').doc('restaurant_delivery').set({ base: 5000, perKm: 1500, version: 1 });
    await expectCode(place(BUYER), 'TARIFF_NOT_CONFIGURED');
    await t.set(TARIFF);
  });
  await check('F3 avaFeeBps > 0 → AVA_FEE_NOT_SUPPORTED (fail closed); admin callable фақат 0 қабул қилади', async () => {
    await db.collection('settings').doc('business_delivery').set({ ...TARIFF, avaFeeBps: 200 });
    await expectCode(place(BUYER), 'AVA_FEE_NOT_SUPPORTED');
    await db.collection('settings').doc('business_delivery').set(TARIFF);
    await expectCode(call('adminSetBusinessDeliveryTariff', { base: 6000, perKm: 1500, avaFeeBps: 100, reason: 'test' }, ADMIN), 'AVA_FEE_NOT_SUPPORTED');
    await assert.rejects(call('adminSetBusinessDeliveryTariff', { base: 6000, perKm: 1500, reason: 'test' }, BUYER));
  });
  await check('F4 adminSetBusinessDeliveryTariff: версия+1, ўзгармас тарих v{n}, audit, avaFeeBps 0; adminSetBusinessOrdersConfig: audit, телефонлар яширин', async () => {
    const r = await call('adminSetBusinessDeliveryTariff', { ...TARIFF, version: undefined, reason: 'narx sinovi' }, ADMIN);
    assert.strictEqual(r.version, TARIFF.version + 1);
    const cur = (await db.collection('settings').doc('business_delivery').get()).data();
    assert.strictEqual(cur.avaFeeBps, 0);
    assert.strictEqual(cur.base, TARIFF.base);
    const h = (await db.collection('business_delivery_tariffs').doc(`v${r.version}`).get()).data();
    assert.strictEqual(h.previous.version, TARIFF.version);
    const audits = (await db.collection('admin_audit').where('kind', '==', 'business_delivery_tariff').get()).size;
    assert.strictEqual(audits, 1);
    const c = await call('adminSetBusinessOrdersConfig', { stage: 'public', addTesterIds: [BUYER2], reason: 'sinov' }, ADMIN);
    assert.strictEqual(c.testerCount, 1);
    const a = (await db.collection('admin_audit').where('kind', '==', 'business_orders_config').get()).docs[0].data();
    assert.ok(!JSON.stringify(a).includes(BUYER2), 'audit\'да тўлиқ телефон йўқ');
    await expectCode(call('adminSetBusinessOrdersConfig', { stage: 'beta', reason: 'xx1' }, ADMIN), 'STAGE_INVALID');
    await db.collection('settings').doc('business_delivery').set(TARIFF);
  });

  // ── 3. Жойлаш ───────────────────────────────────────────────────────
  let o1;
  await check('P1 нарх ФАҚАТ каталогдан (клиент price/total эътиборсиз), снимок, тариф версияси, avaFee 0, placed, код, ҳодиса', async () => {
    const r = await place(BUYER, {
      items: [{ itemId: 'p1', qty: 2, price: 1, unitPrice: 1 }, { itemId: 'p2', qty: 3, price: 1 }],
      itemsTotal: 5, deliveryFee: 0, total: 5, sellerUid: STRANGER, avaFee: { rateBps: 9999 },
    });
    o1 = r.orderId;
    assert.strictEqual(r.itemsTotal, 2 * 20000 + 3 * 5000);
    assert.strictEqual(r.deliveryFee, fee);
    assert.strictEqual(r.total, 55000 + fee);
    assert.strictEqual(r.deliveryTariffVersion, TARIFF.version);
    const od = await order(o1);
    assert.strictEqual(od.type, 'business');
    assert.strictEqual(od.businessStatus, 'placed');
    assert.strictEqual(od.status, 'new');
    assert.strictEqual(od.fulfillmentStatus, 'pending');
    assert.strictEqual(od.sellerUid, SELLER, 'сотувчи — businesses.ownerId, клиентдан эмас');
    assert.strictEqual(od.userPhone, BUYER);
    assert.strictEqual(od.businessId, 'biz1');
    assert.deepStrictEqual([od.businessLat, od.businessLng], [B_LOC.lat, B_LOC.lng]);
    assert.deepStrictEqual([od.lat, od.lng], [C_LOC.lat, C_LOC.lng]);
    assert.strictEqual(od.regionId, 'xorazm');
    assert.strictEqual(od.districtId, 'gurlan');
    assert.deepStrictEqual(od.items, [
      { itemId: 'p1', title: 'Kitob', unitPrice: 20000, priceUnit: '', qty: 2, lineTotal: 40000 },
      { itemId: 'p2', title: 'Olma', unitPrice: 5000, priceUnit: 'kg', qty: 3, lineTotal: 15000 },
    ]);
    assert.strictEqual(od.deliveryTariffVersion, TARIFF.version);
    assert.strictEqual(od.deliveryTariffSnapshot.base, TARIFF.base);
    assert.strictEqual(od.deliveryTariffSnapshot.perKm, TARIFF.perKm);
    assert.deepStrictEqual(od.avaFee, { rateBps: 0, basis: 55000, amount: 0, version: 1, settingsVersion: TARIFF.version, rateSource: 'default', charged: false });
    assert.strictEqual(od.goodsPaymentMethod, 'cash_buyout');
    assert.strictEqual(od.deliveryPaymentMethod, 'wallet');
    assert.strictEqual(od.courierId, null);
    assert.ok(Number.isInteger(od.deliveryFee) && Number.isInteger(od.total), 'пул — бутун сўм');
    assert.ok(od.acceptDeadlineAt.toMillis() > Date.now() + 14 * 60 * 1000, 'deadline ~15 дақ');
    assert.match((await secret(o1)).pickupCode, /^\d{4}$/);
    const ev = await eventsOf(o1);
    assert.strictEqual(ev.length, 1);
    assert.strictEqual(ev[0].to, 'placed');
    assert.strictEqual(await pcBal(BUYER), 100000, 'жойлашда пул ҳаракати йўқ');
  });
  await check('P2 эски `kind`сиз ҳужжат — product (rules сукути); дона/кг/м² — мумкин', async () => {
    const r = await place(BUYER, { items: [{ itemId: 'p3', qty: 1 }] });
    assert.strictEqual(r.itemsTotal, 1000);
  });
  await check('P3 хизмат → ITEM_NOT_PRODUCT; «дан»/соат → PRICE_NOT_FIXED; нарх 0 → ITEM_PRICE_INVALID; pending → ITEM_UNAVAILABLE; бошқа объект/эга → ITEM_NOT_IN_BUSINESS; йўқ → ITEM_NOT_FOUND', async () => {
    await expectCode(place(BUYER, { items: [{ itemId: 'svc', qty: 1 }] }), 'ITEM_NOT_PRODUCT', 'failed-precondition');
    await expectCode(place(BUYER, { items: [{ itemId: 'p1', qty: 1 }, { itemId: 'svc', qty: 1 }] }), 'ITEM_NOT_PRODUCT');
    await expectCode(place(BUYER, { items: [{ itemId: 'pFrom', qty: 1 }] }), 'PRICE_NOT_FIXED');
    await expectCode(place(BUYER, { items: [{ itemId: 'pHour', qty: 1 }] }), 'PRICE_NOT_FIXED');
    await expectCode(place(BUYER, { items: [{ itemId: 'pZero', qty: 1 }] }), 'ITEM_PRICE_INVALID');
    await expectCode(place(BUYER, { items: [{ itemId: 'pPending', qty: 1 }] }), 'ITEM_UNAVAILABLE');
    await expectCode(place(BUYER, { items: [{ itemId: 'pOther', qty: 1 }] }), 'ITEM_NOT_IN_BUSINESS');
    await expectCode(place(BUYER, { items: [{ itemId: 'pForged', qty: 1 }] }), 'ITEM_NOT_IN_BUSINESS');
    await expectCode(place(BUYER, { items: [{ itemId: 'nope', qty: 1 }] }), 'ITEM_NOT_FOUND');
    await expectCode(place(BUYER, { items: [] }), 'ITEMS_REQUIRED', 'invalid-argument');
    await expectCode(place(BUYER, { items: [{ itemId: 'p1', qty: 60 }, { itemId: 'p1', qty: 60 }] }), 'QTY_LIMIT_EXCEEDED');
    await expectCode(place(BUYER, { items: [{ itemId: 'p1', qty: 1.5 }] }), 'ITEM_INVALID');
  });
  await check('P4 ўз объекти → OWN_BUSINESS; онлайн объект → BUSINESS_ONLINE_NO_PICKUP; блокланган → BUSINESS_NOT_ACTIVE; манзилсиз → DELIVERY_ADDRESS_REQUIRED; узоқ → DELIVERY_TOO_FAR', async () => {
    await expectCode(place(BUYER, { businessId: 'bizBuyer', items: [{ itemId: 'pOwn', qty: 1 }] }), 'OWN_BUSINESS');
    await expectCode(place(SELLER, { items: [{ itemId: 'p1', qty: 1 }] }), 'OWN_BUSINESS');
    await expectCode(place(BUYER, { businessId: 'bizOnline', items: [{ itemId: 'pOnline', qty: 1 }] }), 'BUSINESS_ONLINE_NO_PICKUP');
    await db.collection('businesses').doc('biz2').update({ status: 'blocked' });
    await expectCode(place(BUYER, { businessId: 'biz2', items: [{ itemId: 'pOther', qty: 1 }] }), 'BUSINESS_NOT_ACTIVE');
    await db.collection('businesses').doc('biz2').update({ status: 'active' });
    await expectCode(place(BUYER, { lat: null, lng: null }), 'DELIVERY_ADDRESS_REQUIRED');
    await expectCode(place(BUYER, { lat: 41.30, lng: 69.24 }), 'DELIVERY_TOO_FAR');
    await expectCode(place(BUYER, { deliveryPaymentMethod: 'card' }), 'DELIVERY_PAYMENT_INVALID');
    await expectCode(place(BUYER, { goodsPaymentMethod: 'prepay' }), 'GOODS_PAYMENT_INVALID');
  });
  await check('P5 идемпотент: бир калит икки марта → бир буюртма (duplicate); параллел икки чақирув → битта orderId; бошқа фойдаланувчи калити → IDEMPOTENCY_KEY_CONFLICT', async () => {
    const k = key();
    const a = await place(BUYER, { idempotencyKey: k });
    const b = await place(BUYER, { idempotencyKey: k });
    assert.strictEqual(b.orderId, a.orderId);
    assert.strictEqual(b.duplicate, true);
    const k2 = key();
    const [x, y] = await Promise.all([place(BUYER, { idempotencyKey: k2 }), place(BUYER, { idempotencyKey: k2 })]);
    assert.strictEqual(x.orderId, y.orderId, 'параллел — битта буюртма');
    const n = (await db.collection('orders').where('userPhone', '==', BUYER).get()).docs.filter((d) => [a.orderId, x.orderId].includes(d.id)).length;
    assert.strictEqual(n, 2);
    await expectCode(place(BUYER2, { idempotencyKey: k }), 'IDEMPOTENCY_KEY_CONFLICT');
    await expectCode(place(BUYER, { idempotencyKey: 'short' }), 'IDEMPOTENCY_KEY_INVALID');
  });
  await check('P6 quoteBusinessOrder: ёзувсиз нарх; place билан бир хил', async () => {
    const before = (await db.collection('orders').get()).size;
    const q = await call('quoteBusinessOrder', { businessId: 'biz1', items: [{ itemId: 'p1', qty: 2 }, { itemId: 'p2', qty: 3 }], ...C_LOC }, BUYER);
    assert.strictEqual(q.itemsTotal, 55000);
    assert.strictEqual(q.deliveryFee, fee);
    assert.strictEqual(q.total, 55000 + fee);
    assert.strictEqual(q.deliveryTariffVersion, TARIFF.version);
    assert.deepStrictEqual(q.goodsPaymentMethods, ['cash_buyout']);
    assert.strictEqual(q.avaFeeBps, 0);
    assert.strictEqual((await db.collection('orders').get()).size, before);
  });

  // ── 4. Сотувчи ва ўтишлар ───────────────────────────────────────────
  await check('S1 фақат сотувчи қабул қилади: бегона/харидор/курьер → NOT_ORDER_SELLER; сотувчи → accepted; такрор — idempotent', async () => {
    await expectCode(call('businessAcceptOrder', { orderId: o1 }, STRANGER), 'NOT_ORDER_SELLER', 'permission-denied');
    await expectCode(call('businessAcceptOrder', { orderId: o1 }, BUYER), 'NOT_ORDER_SELLER');
    await expectCode(call('businessAcceptOrder', { orderId: o1 }, COURIER_A), 'NOT_ORDER_SELLER');
    await expectCode(call('businessMarkReady', { orderId: o1 }, STRANGER), 'NOT_ORDER_SELLER');
    await expectCode(call('businessRejectOrder', { orderId: o1 }, STRANGER), 'NOT_ORDER_SELLER');
    const r = await call('businessAcceptOrder', { orderId: o1 }, SELLER);
    assert.strictEqual(r.idempotent, false);
    const od = await order(o1);
    assert.strictEqual(od.businessStatus, 'accepted');
    assert.strictEqual(od.status, 'accepted');
    assert.strictEqual(od.acceptDeadlineAt, null);
    assert.strictEqual((await call('businessAcceptOrder', { orderId: o1 }, SELLER)).idempotent, true);
    assert.strictEqual((await eventsOf(o1)).length, 2);
  });
  await check('S2 нотўғри ўтиш: placed → ready → ORDER_INVALID_TRANSITION; accepted дан кейин мижоз бекори → CANCEL_NOT_ALLOWED; рад этилгандан кейин қабул → ORDER_INVALID_TRANSITION', async () => {
    const r = await place(BUYER);
    await expectCode(call('businessMarkReady', { orderId: r.orderId }, SELLER), 'ORDER_INVALID_TRANSITION', 'failed-precondition');
    await expectCode(call('customerCancelBusinessOrder', { orderId: o1 }, BUYER), 'CANCEL_NOT_ALLOWED');
    await call('businessRejectOrder', { orderId: r.orderId, reason: 'tugadi' }, SELLER);
    await expectCode(call('businessAcceptOrder', { orderId: r.orderId }, SELLER), 'ORDER_INVALID_TRANSITION');
    const od = await order(r.orderId);
    assert.strictEqual(od.businessStatus, 'rejected');
    assert.strictEqual(od.status, 'rejected');
    // Ресторан callable'и бизнес буюртмасини рад этади (бир ҳужжат — бир жадвал).
    await expectCode(call('restaurantAcceptOrder', { orderId: o1 }, SELLER), 'NOT_RESTAURANT_ORDER');
  });
  await check('S3 мижоз бекори: фақат ўзи ва фақат placed; такрор — idempotent', async () => {
    const r = await place(BUYER);
    await expectCode(call('customerCancelBusinessOrder', { orderId: r.orderId }, BUYER2), 'NOT_ORDER_OWNER', 'permission-denied');
    assert.strictEqual((await call('customerCancelBusinessOrder', { orderId: r.orderId }, BUYER)).idempotent, false);
    assert.strictEqual((await call('customerCancelBusinessOrder', { orderId: r.orderId }, BUYER)).idempotent, true);
    assert.strictEqual((await order(r.orderId)).businessStatus, 'cancelled');
  });

  // ── 5. Эски йўллар ──────────────────────────────────────────────────
  await check('L1 эски callable\'лар: courierListReadyOrders кўрмайди, courierCreateRoute → no_ready_orders, customerCancelOrder → USE_BUSINESS_CANCEL, adminSetOrderStatus(+Batch) → BUSINESS_ORDER_READONLY', async () => {
    await call('businessMarkReady', { orderId: o1 }, SELLER);
    const od = await order(o1);
    assert.strictEqual(od.status, 'ready', 'эски `status` ҳам ready (кўзгу) — шунинг учун гард шарт');
    const ready = await call('courierListReadyOrders', {}, COURIER_B);
    assert.ok(!ready.orders.some((x) => x.id === o1), 'бизнес буюртмаси эски рўйхатда йўқ');
    await expectCode(call('courierCreateRoute', { courierPhone: COURIER_B, orderedOrderIds: [o1] }, COURIER_B), 'no_ready_orders');
    await expectCode(call('customerCancelOrder', { orderId: o1 }, BUYER), 'USE_BUSINESS_CANCEL');
    await expectCode(call('adminSetOrderStatus', { adminPhone: ADMIN, orderId: o1, status: 'delivered' }, ADMIN), 'BUSINESS_ORDER_READONLY');
    const batch = await call('adminSetOrderStatusBatch', { adminPhone: ADMIN, orderIds: [o1], status: 'rejected' }, ADMIN);
    assert.strictEqual(batch.updated, 0);
    assert.strictEqual((await order(o1)).businessStatus, 'ready', 'ҳолат ўзгармади');
  });

  // ── 6. Курьер ───────────────────────────────────────────────────────
  await check('C1 listNearbyBusinessOrders: проекция (телефон/манзил йўқ), мижоз ва сотувчи ўзиникини кўрмайди', async () => {
    const l = await call('listNearbyBusinessOrders', { ...B_LOC }, COURIER_A);
    const it = l.orders.find((x) => x.id === o1);
    assert.ok(it, 'рўйхатда');
    assert.strictEqual(it.buyoutAmount, 55000);
    assert.strictEqual(it.deliveryFee, fee);
    assert.strictEqual(it.buyoutAllowed, true);
    const s = JSON.stringify(it);
    assert.ok(!s.includes(BUYER) && !s.includes('Mijoz uyi') && !('lat' in it), 'мижоз ПИИ йўқ');
    await expectCode(call('listNearbyBusinessOrders', {}, STRANGER), 'Courier not authorized');
  });
  await check('C2 иккита курьер бир вақтда → БИТТА ғолиб (COURIER_ASSIGNMENT_CONFLICT), маршрутга қўшилди; ғолиб такрори — idempotent', async () => {
    const rs = await Promise.allSettled([
      call('courierClaimBusinessOrder', { orderId: o1 }, COURIER_A),
      call('courierClaimBusinessOrder', { orderId: o1 }, COURIER_B),
    ]);
    const ok = rs.filter((r) => r.status === 'fulfilled');
    const bad = rs.filter((r) => r.status === 'rejected');
    assert.strictEqual(ok.length, 1, 'битта ғолиб');
    const code = bad[0].reason.details && bad[0].reason.details.code;
    assert.ok(['COURIER_ASSIGNMENT_CONFLICT', 'CONTENTION_RETRY'].includes(code), `ютқазган коди ${code}`);
    const od = await order(o1);
    const winner = od.courierId;
    assert.ok([COURIER_A, COURIER_B].includes(winner));
    const route = (await db.collection('delivery_routes').doc(od.deliveryRouteId).get()).data();
    assert.deepStrictEqual(route.orders, [o1]);
    assert.strictEqual(route.courierId, winner);
    assert.strictEqual((await call('courierClaimBusinessOrder', { orderId: o1 }, winner)).idempotent, true);
    // Тест давоми COURIER_A билан: ғолиб B бўлса — алмаштирамиз (маршрут ҳам).
    if (winner !== COURIER_A) {
      await db.collection('orders').doc(o1).update({ courierId: COURIER_A });
      await db.collection('delivery_routes').doc(od.deliveryRouteId).update({ courierId: COURIER_A });
    }
  });
  await check('C3 claim чекловлари: вэкуп лимити → BUYOUT_LIMIT_EXCEEDED; сотувчи курьер → COURIER_IS_SELLER; мижоз курьер → COURIER_OWN_ORDER', async () => {
    const r = await place(BUYER);
    await call('businessAcceptOrder', { orderId: r.orderId }, SELLER);
    await db.collection('restaurant_courier_prefs').doc(COURIER_B).set({ buyoutEnabled: true, buyoutLimit: 1000 });
    await expectCode(call('courierClaimBusinessOrder', { orderId: r.orderId }, COURIER_B), 'BUYOUT_LIMIT_EXCEEDED');
    await db.collection('restaurant_courier_prefs').doc(COURIER_B).set({ buyoutEnabled: true, buyoutLimit: 500000 });
    // Сотувчини курьер қилиб кўрамиз.
    await db.collection('users').doc(SELLER).set({ accountId: 'accBIZ0000000SELL' }, { merge: true });
    await db.collection('provider_capabilities').doc('accBIZ0000000SELL').set({ identity: { accountId: 'accBIZ0000000SELL', primaryUid: SELLER }, courier: { active: true }, status: { courier: 'approved' } });
    await expectCode(call('courierClaimBusinessOrder', { orderId: r.orderId }, SELLER), 'COURIER_IS_SELLER');
    await db.collection('users').doc(BUYER).set({ accountId: 'accBIZ00000000BUY' }, { merge: true });
    await db.collection('provider_capabilities').doc('accBIZ00000000BUY').set({ identity: { accountId: 'accBIZ00000000BUY', primaryUid: BUYER }, courier: { active: true }, status: { courier: 'approved' } });
    await expectCode(call('courierClaimBusinessOrder', { orderId: r.orderId }, BUYER), 'COURIER_OWN_ORDER');
    await call('businessRejectOrder', { orderId: r.orderId }, SELLER);
  });
  await check('C4 эски курьер йўллари маршрутдаги бизнес буюртмасини рад этади: courierMarkPicked → USE_BUSINESS_PICKUP, courierSubmitPayment → USE_BUSINESS_COMPLETION', async () => {
    await expectCode(call('courierMarkPicked', { orderId: o1, courierPhone: COURIER_A }, COURIER_A), 'USE_BUSINESS_PICKUP');
    await expectCode(call('courierSubmitPayment', { orderId: o1, courierPhone: COURIER_A, lines: [{ kind: 'cash', amount: 1000 }] }, COURIER_A), 'USE_BUSINESS_COMPLETION');
  });
  await check('C5 олиб кетиш: нотўғри код → PICKUP_CODE_MISMATCH (уриниш санади); тўғри → picked, товар пули курьер вэкупи, custody seller→courier; бегона курьер → рад', async () => {
    await assert.rejects(call('courierPickupBusinessOrder', { orderId: o1, pickupCode: '0000' }, COURIER_B));
    const code = (await secret(o1)).pickupCode;
    const wrong = code === '1111' ? '2222' : '1111';
    await expectCode(call('courierPickupBusinessOrder', { orderId: o1, pickupCode: wrong }, COURIER_A), 'PICKUP_CODE_MISMATCH');
    assert.strictEqual((await secret(o1)).pickupAttempts, 1);
    await expectCode(call('courierCompleteBusinessOrder', { orderId: o1 }, COURIER_A), 'ORDER_INVALID_TRANSITION');
    await call('courierPickupBusinessOrder', { orderId: o1, pickupCode: code }, COURIER_A);
    const od = await order(o1);
    assert.strictEqual(od.businessStatus, 'picked');
    assert.strictEqual(od.status, 'in_delivery');
    assert.strictEqual(od.paymentStatus, 'goods_paid_by_courier');
    assert.strictEqual(od.buyoutAmount, 55000);
    const cu = (await db.collection('custody_events').doc(`biz_${o1}_pickup`).get()).data();
    assert.deepStrictEqual([cu.from, cu.to], [{ kind: 'seller', id: SELLER }, { kind: 'courier', id: COURIER_A }]);
    assert.strictEqual(cu.shipmentId, null);
    assert.strictEqual((await call('courierPickupBusinessOrder', { orderId: o1, pickupCode: code }, COURIER_A)).idempotent, true);
    await expectCode(call('businessRejectOrder', { orderId: o1 }, SELLER), 'ORDER_INVALID_TRANSITION');
  });
  await check('C6 етиб келмасдан якун → ORDER_INVALID_TRANSITION; arrive; якун (ҳамён): мижоз −fee, курьер +fee, журнал bonus:bizDelivery_{id}; такрор — idempotent, баланс ўзгармайди; Σdr == Σcr', async () => {
    await expectCode(call('courierCompleteBusinessOrder', { orderId: o1 }, COURIER_A), 'ORDER_INVALID_TRANSITION');
    await expectCode(call('courierMarkArrived', { orderId: o1, courierPhone: COURIER_A }, COURIER_A), 'USE_BUSINESS_ARRIVE');
    await call('courierArriveBusinessOrder', { orderId: o1 }, COURIER_A);
    assert.strictEqual((await order(o1)).businessStatus, 'arrived');
    const b0 = await pcBal(BUYER);
    const c0 = await pcBal(COURIER_A);
    const r = await call('courierCompleteBusinessOrder', { orderId: o1 }, COURIER_A);
    assert.strictEqual(r.outcome, 'delivered');
    assert.strictEqual(r.walletPaid, fee);
    assert.strictEqual(r.cashCollected, 55000, 'нақд — фақат товар (вэкуп)');
    assert.strictEqual(await pcBal(BUYER), b0 - fee);
    assert.strictEqual(await pcBal(COURIER_A), c0 + fee);
    const j = await db.collection(ledger.COL_JOURNAL).doc(`bonus:bizDelivery_${o1}`).get();
    assert.ok(j.exists, 'журнал калити');
    assert.strictEqual(j.data().amount, fee);
    const again = await call('courierCompleteBusinessOrder', { orderId: o1 }, COURIER_A);
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(await pcBal(BUYER), b0 - fee, 'иккинчи марта ечилмади');
    assert.strictEqual(await pcBal(COURIER_A), c0 + fee);
    const od = await order(o1);
    assert.strictEqual(od.businessStatus, 'delivered');
    assert.strictEqual(od.status, 'delivered');
    assert.strictEqual(od.paymentStatus, 'paid');
    assert.strictEqual(od.deliveryFeeWalletPaid, fee);
    assert.ok((await db.collection('custody_events').doc(`biz_${o1}_delivered`).get()).exists);
    const users = (await db.collection('users').doc(COURIER_A).get()).data();
    assert.strictEqual(users.bonusBalance, fee, 'ҳамён кўзгуси');
    await journalBalanced();
    const ev = (await eventsOf(o1)).map((e) => e.to);
    assert.deepStrictEqual(ev.filter((x, i) => i === 0 || x !== ev[i - 1]), ['placed', 'accepted', 'ready', 'picked', 'arrived', 'delivered']);
  });
  await check('C7 ҳамён етмаса нақдга тушади (deliveryFeeFallback), журнал ёзилмайди', async () => {
    const r = await toArrived();
    void r;
    const r2 = await place(BUYER2, { deliveryPaymentMethod: 'wallet' });
    await call('businessAcceptOrder', { orderId: r2.orderId }, SELLER);
    await call('businessMarkReady', { orderId: r2.orderId }, SELLER);
    await call('courierClaimBusinessOrder', { orderId: r2.orderId }, COURIER_B);
    await call('courierPickupBusinessOrder', { orderId: r2.orderId, pickupCode: (await secret(r2.orderId)).pickupCode }, COURIER_B);
    await call('courierArriveBusinessOrder', { orderId: r2.orderId }, COURIER_B);
    const out = await call('courierCompleteBusinessOrder', { orderId: r2.orderId }, COURIER_B);
    assert.strictEqual(out.walletPaid, 0);
    assert.strictEqual(out.deliveryPaymentMethod, 'cash');
    assert.strictEqual(out.cashCollected, 55000 + fee);
    assert.strictEqual((await order(r2.orderId)).deliveryFeeFallback, 'insufficient_wallet');
    assert.ok(!(await db.collection(ledger.COL_JOURNAL).doc(`bonus:bizDelivery_${r2.orderId}`).get()).exists);
    // Биринчи (r) буюртма ҳам якунлансин — кейинги тестларга курьер маршрути бўш бўлсин.
    await call('courierCompleteBusinessOrder', { orderId: r.orderId }, COURIER_A);
  });

  // ── 7. Жадвал ───────────────────────────────────────────────────────
  await check('E1 сотувчи муддатида қабул қилмади → rejected (timeout), ҳодиса; қабул қилинган буюртмага тегилмайди', async () => {
    const r = await place(BUYER);
    const r2 = await place(BUYER);
    await call('businessAcceptOrder', { orderId: r2.orderId }, SELLER);
    const past = TS.fromMillis(Date.now() - 60 * 1000);
    await db.collection('orders').doc(r.orderId).update({ acceptDeadlineAt: past });
    await db.collection('orders').doc(r2.orderId).update({ acceptDeadlineAt: past });
    const res = await fns.expireUnacceptedBusinessOrders.run({});
    assert.ok(res.expired >= 1);
    const od = await order(r.orderId);
    assert.strictEqual(od.businessStatus, 'rejected');
    assert.strictEqual(od.rejectReason, 'timeout');
    assert.strictEqual((await order(r2.orderId)).businessStatus, 'accepted');
    await call('businessRejectOrder', { orderId: r2.orderId }, SELLER);
  });

  // ── 8. Мижоз тасдиғи (received) ──────────────────────────────────────
  await check('Q1 customer_confirm business=public: курьер якуни → кутиш (пул ҳаракати йўқ); мижоз «Олдим» → delivered, ҳамён ечилди', async () => {
    await db.collection('server_config').doc('customer_confirm').set({ modules: { business: { stage: 'public' } } });
    const r = await toArrived();
    const b0 = await pcBal(BUYER);
    const w = await call('courierCompleteBusinessOrder', { orderId: r.orderId }, COURIER_A);
    assert.deepStrictEqual(w, { ok: true, awaitingCustomer: true, step: 'received' });
    assert.strictEqual((await order(r.orderId)).businessStatus, 'arrived');
    assert.strictEqual(await pcBal(BUYER), b0);
    const p = await call('getCustomerPendingConfirmations', {}, BUYER);
    assert.ok(p.items.some((x) => x.module === 'business' && x.id === r.orderId && x.step === 'received'));
    await expectCode(call('customerConfirmHandover', { module: 'business', id: r.orderId, step: 'received' }, BUYER2), 'NOT_YOUR_ORDER');
    const c = await call('customerConfirmHandover', { module: 'business', id: r.orderId, step: 'received' }, BUYER);
    assert.strictEqual(c.status, 'delivered');
    const od = await order(r.orderId);
    assert.strictEqual(od.businessStatus, 'delivered');
    assert.strictEqual(od.awaitingCustomerConfirm, undefined);
    assert.ok(od.customerConfirmed && od.customerConfirmed.received);
    assert.strictEqual(await pcBal(BUYER), b0 - fee);
    await db.collection('server_config').doc('customer_confirm').delete();
  });

  // ── 9. «Етказилмади» (delivery_failed.js) ────────────────────────────
  await check('D1 курьер «етказилмади» → мижоз тасдиғи → delivery_failed, маршрутдан олинди, товар сотувчига (ҳодиса), пул ҳаракати йўқ', async () => {
    const r = await toArrived();
    const b0 = await pcBal(BUYER);
    const rep = await call('courierReportDeliveryFailed', { module: 'business', id: r.orderId, reason: 'customer_absent' }, COURIER_A);
    assert.strictEqual(rep.awaitingCustomer, true);
    assert.strictEqual((await order(r.orderId)).businessStatus, 'arrived', 'ҳолат ўзгармади');
    await expectCode(call('courierReportDeliveryFailed', { module: 'order', id: r.orderId, reason: 'customer_absent' }, COURIER_A), 'DF_NOT_ACTIVE');
    const p = await call('getCustomerPendingConfirmations', {}, BUYER);
    const it = p.items.find((x) => x.id === r.orderId);
    assert.ok(it && it.module === 'business' && it.step === 'delivery_failed' && it.canReject === true);
    await call('customerConfirmHandover', { module: 'business', id: r.orderId, step: 'delivery_failed', decision: 'confirm' }, BUYER);
    const od = await order(r.orderId);
    assert.strictEqual(od.businessStatus, 'delivery_failed');
    assert.strictEqual(od.status, 'cancelled');
    assert.strictEqual(od.deliveryFailedResolution.by, 'customer');
    const route = (await db.collection('delivery_routes').doc(od.deliveryRouteId).get()).data();
    assert.ok(!route.orders.includes(r.orderId), 'маршрутдан олинди');
    assert.strictEqual(await pcBal(BUYER), b0, 'пул ҳаракати йўқ');
    const ev = await db.collection('delivery_failed_events').where('refId', '==', r.orderId).get();
    assert.ok(ev.docs.some((d) => d.data().kind === 'goods_return_to_seller'));
    assert.ok((await eventsOf(r.orderId)).some((e) => e.to === 'delivery_failed'));
  });
  await check('D2 мижоз жавоб бермади: эски «order» жадвали бизнес белгисини ТОЗАЛАМАЙДИ, бизнес модули эскалация қилади; бегона → DF_NOT_ALLOWED; сотувчи «continue» → курьер давом этади; кейин «failed»', async () => {
    const r = await toArrived();
    await call('courierReportDeliveryFailed', { module: 'business', id: r.orderId, reason: 'customer_refused' }, COURIER_A);
    const past = TS.fromMillis(Date.now() - 60 * 1000);
    await db.collection('orders').doc(r.orderId).update({ deliveryFailedDueAt: past, 'awaitingCustomerConfirm.escalateAt': past });
    await fns.escalateDeliveryFailed.run({});
    let od = await order(r.orderId);
    assert.ok(od.deliveryFailedEscalatedAt, 'эскалация бўлди');
    assert.strictEqual(od.deliveryFailedOpen, true, 'OPEN тозаланмади');
    assert.strictEqual(od.awaitingCustomerConfirm.step, 'delivery_failed');
    const l = await call('listDeliveryFailedPending', {}, SELLER);
    assert.ok(l.items.some((x) => x.module === 'business' && x.id === r.orderId && x.canDecide === true));
    await expectCode(call('listDeliveryFailedPending', {}, BUYER2), 'DF_NOT_ALLOWED');
    await expectCode(call('resolveDeliveryFailed', { module: 'business', id: r.orderId, decision: 'failed' }, STRANGER), 'DF_NOT_ALLOWED');
    await expectCode(call('resolveDeliveryFailed', { module: 'business', id: r.orderId, decision: 'failed' }, COURIER_A), 'DF_NOT_ALLOWED');
    const c = await call('resolveDeliveryFailed', { module: 'business', id: r.orderId, decision: 'continue' }, SELLER);
    assert.strictEqual(c.status, 'in_delivery');
    od = await order(r.orderId);
    assert.strictEqual(od.businessStatus, 'arrived');
    assert.strictEqual(od.deliveryFailedResolution.by, 'seller');
    const audit = await db.collection('admin_audit').where('kind', '==', 'delivery_failed_decision').get();
    assert.ok(audit.docs.some((d) => d.data().target === `orders/${r.orderId}`));
    // Қайта хабар → муддат ўтди → сотувчи «failed».
    await call('courierReportDeliveryFailed', { module: 'business', id: r.orderId, reason: 'customer_absent' }, COURIER_A);
    await db.collection('orders').doc(r.orderId).update({ 'awaitingCustomerConfirm.escalateAt': past });
    const f = await call('resolveDeliveryFailed', { module: 'business', id: r.orderId, decision: 'failed' }, SELLER);
    assert.strictEqual(f.status, 'delivery_failed');
    assert.strictEqual((await order(r.orderId)).businessStatus, 'delivery_failed');
    assert.strictEqual((await call('resolveDeliveryFailed', { module: 'business', id: r.orderId, decision: 'failed' }, SELLER)).idempotent, true);
  });

  // ── 10. Индекс ва якуний текширув ────────────────────────────────────
  await check('X0 order_index: бизнес буюртмаси `business` модули (нон эмас), ҳолат businessStatus дан; admin «қотиб қолган» — алоҳида модул, courier_orders да йўқ', async () => {
    const oi = require('../order_index');
    const n = oi.normalize('orders', { type: 'business', businessStatus: 'picked', status: 'in_delivery', total: 61000, businessName: 'Gurlan kitob', userPhone: BUYER, courierId: COURIER_A });
    assert.strictEqual(n.module, 'business');
    assert.strictEqual(n.normStatus, 'WITH_COURIER');
    assert.strictEqual(n.rawStatus, 'picked');
    assert.strictEqual(n.customerTail, BUYER.slice(-4));
    const st = require('../admin_stale_tasks');
    const courierSpec = st.SPECS.find((s) => s.key === 'courier_orders');
    assert.strictEqual(courierSpec.keep({ type: 'business', status: 'in_delivery' }), false);
    assert.ok(st.SPECS.some((s) => s.key === 'business_orders'));
    const res = await call('adminListStaleTasks', { hours: 1 }, ADMIN);
    assert.ok(res.modules.business_orders, 'жавобда business_orders');
  });
  await check('X1 сверка: Σdr == Σcr барча журналда', async () => {
    assert.ok(await journalBalanced() > 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
