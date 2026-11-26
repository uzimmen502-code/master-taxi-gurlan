/**
 * Байрам саватчаси — callable/trigger/scheduler, ҲАҚИҚИЙ index.js + маҳаллий attach (вақт/хабар DI), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-holiday "node test/holiday_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-holiday';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const h = require('../holiday');
const TAX2 = require('../tools/data/supermarket_taxonomy_v2.json');
const SETTINGS = require('../tools/data/supermarket_settings_v1.json');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001';
const OTHER = '998912000003';
const RECIP = '998912000005';
const OPTOUT = '998912000007';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});
const N = (c, l, r) => ({ uz_Cyrl: c, uz_Latn: l, ru: r || c });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => { assert.strictEqual((e.details && e.details.code) || e.message, code); return true; });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get()).data();
const news = async (source) => (await db.collection('admin_news').where('source', '==', source).get()).docs.map((d) => d.data());
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());
let rq = 0;
const rid = (p = 'req') => `${p}-${String(++rq).padStart(8, '0')}`;
const ADDR = { districtId: 'gurlan', mahalla: 'Navoiy', street: 'Mustaqillik', house: '12', phone: '901234567' };
const todayKey = h.dateKeyOf(Date.now());
const place = (items, extra = {}) => call('placeSupermarketOrder', { clientRequestId: rid('ord'), items, address: ADDR, slotId: 'morning', deliveryDate: h.addDays(todayKey, 1), ...extra }, USER);

// Маҳаллий attach: сохта вақт + хабарларни йиғиш (эслатмалар/тозалаш).
let fakeNow = Date.now();
const sent = [];
const HttpsError = functions.https.HttpsError;
const local = {};
const api = h.attachHoliday(local, {
  functions, db, admin, nowMs: () => fakeNow,
  callerPhone: (c) => String(c.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v).replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
  requireCallerRoles: async (c) => { if (!c || !c.auth) throw new HttpsError('unauthenticated', 'x'); return '0'; },
  notifyUserInApp: async (m) => { sent.push(m); },
});

const BASKET = {
  id: 'birthday_simple', occasionId: 'birthday', tier: 'simple', baseGuests: 10, active: true, names: N('Оддий', 'Oddiy', 'Простая'),
  items: [{ groupId: 'beef', qty: 2, priority: 1 }, { groupId: 'soda', qty: 4, priority: 6 }, { groupId: 'bread', qty: 5, priority: 2 }],
};
const PROGRAM = {
  title: N('Қариндошлар', 'Qarindoşlar', 'Родные'), stage: 'internal', internalPhones: [USER], pilotDistrictIds: [],
  amount: 10000, minRelatives: 3, minOrderAmount: 100000, maxOrderSharePct: 100, validityDays: 30, budgetTotal: 1000000,
};

async function relTrigger(ownerId, personId, data) {
  const ref = db.doc(`relatives/${ownerId}/people/${personId}`);
  const before = await ref.get();
  if (data === null) await ref.delete(); else await ref.set(data);
  const after = await ref.get();
  await fns.onRelativeBirthdayIndex.run({ before, after }, { params: { ownerId, personId } });
}

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${USER}`).set({ role: 'user', name: 'Ali', bonusBalance: 1000000, districtId: 'gurlan', appLang: 'uz_Latn' });
  await db.doc(`users/${OTHER}`).set({ role: 'user', bonusBalance: 500000, districtId: 'gurlan' });
  await db.doc(`users/${RECIP}`).set({ role: 'user', appLang: 'ru' });
  await db.doc(`users/${OPTOUT}`).set({ role: 'user', districtId: 'gurlan', holidayRemindersOptIn: false });
  await db.doc('settings/app').set({ platformDeliveryFeePercent: 11, platformDeliveryFeeVersion: 2 });
  await call('adminSetSupermarketTaxonomy', { taxonomy: TAX2, expectedVersion: 0 }, ADMIN);
  await call('adminSetSupermarketSettings', { settings: { ...SETTINGS, testerIds: [USER, OPTOUT] }, expectedVersion: 0 }, ADMIN);
  const v = (id) => ({ id, names: N('Нав', 'Nav', 'Сорт') });
  const up = (productId, offer) => call('adminUpsertSupermarketOffer', { productId, offer }, ADMIN);
  await up('beef_lean_1', { smGroupId: 'beef', smVariety: v('lean'), stock: 50, smStatus: 'active', price: 80000 });
  await up('beef_bone_1', { smGroupId: 'beef', smVariety: v('bone'), stock: 50, smStatus: 'active', price: 60000 });
  await up('soda_cola_1', { smGroupId: 'soda', smVariety: v('cola'), stock: 100, smStatus: 'active', price: 12000 });
  await up('bread_non_1', { smGroupId: 'bread', smVariety: v('non'), stock: 100, smStatus: 'active', price: 4000 });

  await check('C1 adminUpsertHolidayOccasion: рухсат, текширув, visible, аудит, идемпотент', async () => {
    const occ = { id: 'birthday', kind: 'birthday', names: N('Туғилган кун', 'Tuğilgan kun', 'День рождения'), stage: 'internal', order: 1 };
    await expectCode(call('adminUpsertHolidayOccasion', { occasion: occ }, USER), 'PERMISSION_DENIED');
    await expectCode(call('adminUpsertHolidayOccasion', { occasion: { ...occ, dateRule: { type: 'fixed', md: '03-21' } } }, ADMIN), 'OCCASION_INVALID');
    const r = await call('adminUpsertHolidayOccasion', { occasion: occ }, ADMIN);
    assert.deepStrictEqual([r.changed, r.version], [true, 1]);
    const d = await get('holiday_occasions/birthday');
    assert.deepStrictEqual([d.visible, d.remindDaysBefore], [false, 5]);
    assert.strictEqual((await call('adminUpsertHolidayOccasion', { occasion: occ }, ADMIN)).changed, false);
    await call('adminUpsertHolidayOccasion', { occasion: { id: 'navruz', kind: 'holiday', names: N('Наврўз', 'Navröz', 'Навруз'), stage: 'public', order: 2, dateRule: { type: 'fixed', md: '03-21' } } }, ADMIN);
    assert.strictEqual((await get('holiday_occasions/navruz')).visible, true);
    assert.strictEqual((await audits('holiday_occasion_set')).length, 2);
  });

  await check('C2 adminUpsertHolidayBasket: таксономия гуруҳи, visible каскади (байрам off → сават яширин)', async () => {
    await expectCode(call('adminUpsertHolidayBasket', { basket: { ...BASKET, items: [{ groupId: 'caviar', qty: 1 }] } }, ADMIN), 'BASKET_INVALID');
    await expectCode(call('adminUpsertHolidayBasket', { basket: { ...BASKET, occasionId: 'nope' } }, ADMIN), 'OCCASION_NOT_FOUND');
    await call('adminUpsertHolidayBasket', { basket: BASKET }, ADMIN);
    assert.strictEqual((await get('holiday_baskets/birthday_simple')).visible, false);
    await call('adminUpsertHolidayBasket', { basket: { ...BASKET, id: 'navruz_simple', occasionId: 'navruz' } }, ADMIN);
    assert.strictEqual((await get('holiday_baskets/navruz_simple')).visible, true);
    await call('adminUpsertHolidayOccasion', { occasion: { id: 'navruz', kind: 'holiday', names: N('Наврўз', 'Navröz', 'Навруз'), stage: 'off', order: 2, dateRule: { type: 'fixed', md: '03-21' } } }, ADMIN);
    assert.strictEqual((await get('holiday_baskets/navruz_simple')).visible, false);
    assert.strictEqual((await audits('holiday_basket_set')).length, 2);
  });

  await check('C3 getHolidayCatalog: тестер internal байрамни кўради, бошқаси — йўқ', async () => {
    const r = await call('getHolidayCatalog', {}, USER);
    assert.deepStrictEqual(r.occasions.map((o) => o.id), ['birthday']);
    assert.deepStrictEqual(r.baskets.map((b) => b.id), ['birthday_simple']);
    assert.deepStrictEqual((await call('getHolidayCatalog', {}, OTHER)).occasions, []);
  });

  await check('C4 buildHolidayBasket: сони/бюджет, ўзгаришлар, ҳеч нарса ёзмайди; бегонага NOT_AVAILABLE', async () => {
    const before = (await db.collection('orders').get()).size;
    const r = await call('buildHolidayBasket', { basketId: 'birthday_simple', guests: 5 }, USER);
    assert.deepStrictEqual(r.lines.map((l) => [l.productId, l.qty]), [['beef_bone_1', 1], ['soda_cola_1', 2], ['bread_non_1', 3]]);
    assert.strictEqual(r.goods, 60000 + 24000 + 12000);
    assert.strictEqual(r.fee, Math.floor((96000 * 1100 + 5000) / 10000));
    const b = await call('buildHolidayBasket', { basketId: 'birthday_simple', budget: 150000 }, USER);
    assert.ok(b.changes.some((c) => c.type === 'drop' && c.groupId === 'soda'));
    assert.ok(b.total <= 150000 && b.withinBudget === true);
    await expectCode(call('buildHolidayBasket', { basketId: 'birthday_simple', guests: 0 }, USER), 'INVALID_REQUEST');
    await expectCode(call('buildHolidayBasket', { basketId: 'birthday_simple' }, OTHER), 'NOT_AVAILABLE');
    assert.strictEqual((await db.collection('orders').get()).size, before);
  });

  let giftOrderId;
  await check('C5 совға: +10 кун, олувчи телефони contactPhone, нархсиз хабар олувчига ФАҚАТ курьер олганда (бир марта); +15 кун ва бузуқ gift — рад', async () => {
    const date = h.addDays(todayKey, 10);
    const r = await place([{ productId: 'soda_cola_1', qty: 3 }], {
      deliveryDate: date, origin: 'holiday', occasionId: 'birthday', basketId: 'birthday_simple',
      gift: { recipientName: 'Онам', recipientPhone: '912000005', message: 'Туғилган кунингиз билан!' },
    });
    giftOrderId = r.orderId;
    assert.strictEqual(r.slotDate, date); assert.strictEqual(r.gift, true);
    const o = await get(`orders/${r.orderId}`);
    assert.deepStrictEqual(o.gift, { recipientName: 'Онам', recipientPhone: RECIP, message: 'Туғилган кунингиз билан!', hidePrice: true });
    assert.strictEqual(o.contactPhone, RECIP); assert.strictEqual(o.userPhone, USER);
    assert.deepStrictEqual([o.slot.date, o.slot.day, o.smOrigin, o.smOccasionId, o.smBasketId], [date, 'scheduled', 'holiday', 'birthday', 'birthday_simple']);
    assert.strictEqual(o.giftPurgeAfter.toMillis(), h.startOfKeyMs(date) + 2 * 86400000);
    // Буюртма берилганда олувчига хабар ЙЎҚ (эга 2026-11-27).
    assert.strictEqual((await news('sm_gift_received')).length, 0);
    // Курьерга ўтгач (trigger) — бир марта; қайта ишга тушса — такрор йўқ.
    const ref = db.doc(`orders/${r.orderId}`);
    const fire = async (patch) => { const before = await ref.get(); await ref.update(patch); await fns.onSupermarketOrderCancelStock.run({ before, after: await ref.get() }, { params: { orderId: r.orderId } }); };
    await fire({ status: 'accepted' });
    await fire({ status: 'ready' });
    assert.strictEqual((await news('sm_gift_received')).length, 0);
    await fire({ status: 'in_delivery', fulfillmentStatus: 'courier_picked' });
    let n = await news('sm_gift_received');
    assert.strictEqual(n.length, 1); assert.strictEqual(n[0].targetUserId, RECIP);
    assert.ok(!/\d/.test(n[0].body) && !n[0].body.includes('сум'), n[0].body); // нарх йўқ
    assert.ok((await get(ref.path)).giftNotifiedAt);
    await fire({ fulfillmentStatus: 'arrived' });
    const snap = await ref.get();
    await fns.onSupermarketOrderCancelStock.run({ before: snap, after: snap }, { params: { orderId: r.orderId } }); // retry
    n = await news('sm_gift_received');
    assert.strictEqual(n.length, 1);
    // Совғасиз буюртма курьерга ўтса — хабар йўқ; бекор қилинган совға — хабар йўқ.
    const plain = await place([{ productId: 'bread_non_1', qty: 1 }]);
    const pRef = db.doc(`orders/${plain.orderId}`);
    let b = await pRef.get(); await pRef.update({ status: 'in_delivery' });
    await fns.onSupermarketOrderCancelStock.run({ before: b, after: await pRef.get() }, { params: { orderId: plain.orderId } });
    const g2 = await place([{ productId: 'bread_non_1', qty: 1 }], { gift: { recipientName: 'Ака', recipientPhone: '912000005' } });
    const g2Ref = db.doc(`orders/${g2.orderId}`);
    b = await g2Ref.get(); await g2Ref.update({ status: 'cancelled' });
    await fns.onSupermarketOrderCancelStock.run({ before: b, after: await g2Ref.get() }, { params: { orderId: g2.orderId } });
    assert.strictEqual((await news('sm_gift_received')).length, 1);
    assert.strictEqual((await get(g2Ref.path)).giftNotifiedAt, undefined);
    await expectCode(place([{ productId: 'soda_cola_1', qty: 1 }], { deliveryDate: h.addDays(todayKey, 15) }), 'SLOT_UNAVAILABLE');
    await expectCode(place([{ productId: 'soda_cola_1', qty: 1 }], { gift: { recipientName: 'A', recipientPhone: '12' } }), 'INVALID_REQUEST');
    // эски клиент (day) ўзгармади
    const old = await call('placeSupermarketOrder', { clientRequestId: rid('ord'), items: [{ productId: 'bread_non_1', qty: 1 }], address: ADDR, slotId: 'morning', day: 'tomorrow' }, USER);
    assert.strictEqual((await get(`orders/${old.orderId}`)).slot.day, 'tomorrow');
    assert.ok((await call('getSupermarketAccess', { withDates: true }, USER)).dateSlots.length >= 14);
  });

  await check('C6 совға PII тозалаш (эга 2026-11-27): етказилгандан 1 кун кейин; олдин — кўчирилади; иккинчи марта — ҳеч нарса', async () => {
    const ref = db.doc(`orders/${giftOrderId}`);
    const date = h.addDays(todayKey, 10);
    fakeNow = h.startOfKeyMs(date) + 2 * 86400000 + 3600000; // giftPurgeAfter дан 1 соат кейин (соатлик сканер)
    await ref.update({ status: 'delivered', deliveredAt: admin.firestore.Timestamp.fromMillis(fakeNow - 23 * 3600000) });
    let r = await api.runGiftPiiSweep();
    assert.deepStrictEqual([r.redacted, r.rescheduled], [1, 1]); // C5 даги бекор қилинган совға (g2) — тозаланди
    assert.strictEqual((await get(ref.path)).gift.recipientPhone, RECIP);
    assert.strictEqual((await get(ref.path)).giftPurgeAfter.toMillis(), fakeNow + 3600000);
    fakeNow += 3600000;
    r = await api.runGiftPiiSweep();
    assert.deepStrictEqual([r.redacted, r.rescheduled], [1, 0]);
    const o = await get(ref.path);
    assert.deepStrictEqual(o.gift, { recipientName: '', recipientPhone: '', message: '', hidePrice: true, redacted: true });
    assert.deepStrictEqual([o.contactPhone, o.address, o.addressParts, o.giftPurgeAfter, o.lat], ['', '', { districtId: 'gurlan' }, undefined, undefined]);
    assert.strictEqual(o.total > 0 && o.userPhone === USER, true); // молиявий майдонлар қолади
    assert.strictEqual((await api.runGiftPiiSweep()).scanned, 0);
    fakeNow = Date.now();
  });

  await check('C7 қариндошлар: индекс (исмсиз), 3-қариндошда бонус бир марта, умумий claimIncentive бермайди', async () => {
    await expectCode(call('adminUpsertRelativesBonusProgram', { program: { ...PROGRAM, amount: 0 } }, ADMIN), 'PROGRAM_INVALID');
    await call('adminUpsertRelativesBonusProgram', { program: PROGRAM }, ADMIN);
    const bd = admin.firestore.Timestamp.fromMillis(Date.UTC(1965, 2, 20, 19)); // 21-март Тошкент
    await relTrigger(USER, 'p1', { firstName: 'Лола', fullName: 'Лола', birthDate: bd });
    await relTrigger(USER, 'p2', { firstName: 'Ҳасан', birthDate: admin.firestore.Timestamp.fromMillis(Date.UTC(1990, 5, 1, 19)) });
    await relTrigger(USER, 'p0', { firstName: 'Мен', birthDate: bd, isSelf: true });
    assert.strictEqual((await db.collection('incentive_grants').get()).size, 0);
    const ix = await get(`holiday_birthday_index/${USER}_p1`);
    assert.deepStrictEqual(Object.keys(ix).sort(), ['md', 'ownerId', 'personId', 'updatedAt']);
    assert.strictEqual(ix.md, '03-21');
    assert.strictEqual(await get(`holiday_birthday_index/${USER}_p0`), undefined);
    await relTrigger(USER, 'p3', { firstName: 'Зуҳра', birthDate: admin.firestore.Timestamp.fromMillis(Date.UTC(1992, 7, 9, 19)) });
    const g = await get(`incentive_grants/relatives_birthdays_${USER}`);
    assert.deepStrictEqual([g.amount, g.remaining, g.status, g.minOrderAmount, g.buckets], [10000, 10000, 'active', 100000, { supermarket: 10000 }]);
    assert.strictEqual((await get(`users/${USER}`)).incentiveBalance, 10000);
    assert.ok(await get(`incentive_ledger/grant_relatives_birthdays_${USER}`));
    await relTrigger(USER, 'p4', { firstName: 'Ака', birthDate: bd });
    assert.strictEqual((await get(`users/${USER}`)).incentiveBalance, 10000);
    assert.strictEqual((await call('claimRelativesBonus', {}, USER)).result, 'duplicate');
    await relTrigger(USER, 'p4', null); // ўчирилса — грант қолади
    assert.strictEqual(await get(`holiday_birthday_index/${USER}_p4`), undefined);
    assert.strictEqual((await get(`incentive_grants/relatives_birthdays_${USER}`)).status, 'active');
    assert.strictEqual((await call('claimRelativesBonus', {}, OTHER)).code, 'NOT_IN_STAGE');
    const prog = await get('incentive_programs/relatives_birthdays');
    assert.strictEqual(prog.audience.newUsersSince, undefined); // умумий claimIncentive → NOT_NEW_USER
    assert.strictEqual(prog.counters.grantedCount, 1);
  });

  let incOrderId;
  await check('C8 бонус буюртмада: min order, бир марта, нетто ҳамён ечими, грант сарфланди', async () => {
    const bal0 = (await get(`users/${USER}`)).bonusBalance;
    const small = await place([{ productId: 'soda_cola_1', qty: 2 }], { useIncentive: true });
    assert.strictEqual(small.incentiveApplied, undefined);
    assert.strictEqual((await get(`users/${USER}`)).bonusBalance, bal0 - small.total);
    const bal1 = (await get(`users/${USER}`)).bonusBalance;
    const r = await place([{ productId: 'beef_lean_1', qty: 1 }, { productId: 'soda_cola_1', qty: 3 }], { useIncentive: true });
    incOrderId = r.orderId;
    // goods 116000, тортиш +10% (beef) 8000, fee 11% 12760 → брутто 136760; бонус 10000 → нетто 126760
    assert.deepStrictEqual([r.grossTotal, r.incentiveApplied, r.total, r.walletDebit], [136760, 10000, 126760, 126760]);
    const o = await get(`orders/${r.orderId}`);
    assert.deepStrictEqual([o.balanceApplied, o.incentiveApplied, o.incentiveUid, o.grossTotal], [126760, 10000, USER, 136760]);
    assert.strictEqual((await get(`users/${USER}`)).bonusBalance, bal1 - 126760);
    assert.strictEqual((await get(`users/${USER}`)).incentiveBalance, 0);
    assert.deepStrictEqual([(await get(`incentive_grants/relatives_birthdays_${USER}`)).status], ['spent']);
    assert.ok(await get(`incentive_ledger/spend_${r.orderId}_relatives_birthdays_${USER}`));
    const again = await place([{ productId: 'beef_lean_1', qty: 1 }, { productId: 'soda_cola_1', qty: 3 }], { useIncentive: true });
    assert.strictEqual(again.incentiveApplied, undefined);
  });

  await check('C9 тузатиш (қаторни олиш) бонусли буюртмада: қайтим нетто, бонус нақдга айланмайди', async () => {
    const bal = (await get(`users/${USER}`)).bonusBalance;
    const rm = await call('adminRemoveSupermarketLine', { orderId: incOrderId, productId: 'soda_cola_1', reason: 'Тугади' }, ADMIN);
    // янги брутто: 80000 + 8000 + 8800 = 96800; нетто 86800; қайтим 126760 − 86800 = 39960
    assert.strictEqual(rm.refund, 39960);
    const o = await get(`orders/${incOrderId}`);
    assert.deepStrictEqual([o.balanceApplied, o.grossTotal, o.incentiveApplied], [86800, 96800, 10000]);
    assert.strictEqual((await get(`users/${USER}`)).bonusBalance, bal + 39960);
  });

  await check('C10 бекор: грант тикланади (бир марта, idempotent), stock қайтади', async () => {
    const ref = db.doc(`orders/${incOrderId}`);
    const before = await ref.get();
    await ref.update({ status: 'cancelled' });
    const after = await ref.get();
    await fns.onSupermarketOrderCancelStock.run({ before, after }, { params: { orderId: incOrderId } });
    const g = await get(`incentive_grants/relatives_birthdays_${USER}`);
    assert.deepStrictEqual([g.status, g.remaining], ['active', 10000]);
    assert.strictEqual((await get(`users/${USER}`)).incentiveBalance, 10000);
    assert.ok(await get(`incentive_ledger/refund_${incOrderId}_relatives_birthdays_${USER}`));
    await ref.update({ smStockRestored: false });
    await fns.onSupermarketOrderCancelStock.run({ before, after: await ref.get() }, { params: { orderId: incOrderId } });
    assert.strictEqual((await get(`users/${USER}`)).incentiveBalance, 10000); // иккинчи марта қўшилмади
  });

  await check('C11 эслатмалар: туғилган кун (5 кун) + Наврўз; опт-аут; қайта ишга тушса — такрор йўқ', async () => {
    await call('adminUpsertHolidayOccasion', { occasion: { id: 'navruz', kind: 'holiday', names: N('Наврўз', 'Navröz', 'Навруз'), stage: 'public', order: 2, dateRule: { type: 'fixed', md: '03-21' } } }, ADMIN);
    fakeNow = h.startOfKeyMs('2027-03-16') + 9 * 3600000;
    sent.length = 0;
    const r = await api.runHolidayRemindersAll();
    const bd = sent.filter((m) => m.source === 'holiday_birthday_reminder');
    assert.strictEqual(bd.length, 1, JSON.stringify(sent.map((m) => m.body))); // фақат p1 (Лола, 21-март); p4 ўчирилган, p0 «Мен»
    assert.ok(bd.every((m) => m.userId === USER && m.body.includes('5 kun')));
    assert.ok(bd.some((m) => m.body.startsWith('Лолаning')));
    const hol = sent.filter((m) => m.source === 'holiday_reminder');
    assert.deepStrictEqual(hol.map((m) => m.userId), [USER, ADMIN]); // супермаркет internal: тестер + админ; OPTOUT — opt-out; OTHER — супермаркет тестери эмас
    assert.ok(hol[0].body.startsWith('Navröz'));
    assert.strictEqual(r.holidays.occasions, 1);
    sent.length = 0;
    await api.runHolidayRemindersAll();
    assert.strictEqual(sent.length, 0);
    fakeNow = Date.now();
  });

  // ── эга 2026-11-27 ──
  const LEG = '912000009'; const LEGC = `998${LEG}`; // фақат эски 9 хонали users ҳужжати
  const DUAL = '998912000011'; const DUAL9 = DUAL.slice(3); // бир шахснинг иккала ҳужжати
  const bdTs = (y, m, d) => admin.firestore.Timestamp.fromMillis(Date.UTC(y, m - 1, d - 1, 19));
  await check('C12 бонус барча телефон шаклларида: эски 9 хонали ҳисоб олади; бир шахснинг 2 ҳужжати — БИТТА грант', async () => {
    await db.doc(`users/${LEG}`).set({ role: 'user', name: 'Eski', bonusBalance: 500000, districtId: 'gurlan', appLang: 'ru' });
    await db.doc(`users/${DUAL}`).set({ role: 'user', name: 'Dual', bonusBalance: 0, districtId: 'gurlan' });
    await db.doc(`users/${DUAL9}`).set({ role: 'user', name: 'Dual old', bonusBalance: 0, districtId: 'gurlan' });
    const st = (await db.doc('settings/supermarket').get()).data();
    await db.doc('settings/supermarket').update({ testerIds: [...st.testerIds, LEGC, DUAL] });
    await call('adminUpsertRelativesBonusProgram', { program: { ...PROGRAM, internalPhones: [USER, LEGC, DUAL] } }, ADMIN);
    // эски ҳисоб: қариндошлар иккала relatives ҳужжатида (2 + 1 = 3, такрор санолмайди)
    await relTrigger(LEG, 'a', { firstName: 'Ona', birthDate: bdTs(1960, 4, 1) });
    await relTrigger(LEG, 'b', { firstName: 'Ota', birthDate: bdTs(1958, 5, 2) });
    await relTrigger(LEGC, 'a2', { firstName: 'ona', birthDate: bdTs(1960, 4, 1) }); // ўша одам (исм+сана) — санолмайди
    assert.strictEqual(await get(`incentive_grants/relatives_birthdays_${LEGC}`), undefined);
    await relTrigger(LEGC, 'c', { firstName: 'Opa', birthDate: bdTs(1985, 6, 3) });
    const g = await get(`incentive_grants/relatives_birthdays_${LEGC}`);
    assert.deepStrictEqual([g.uid, g.personKey, g.amount, g.status], [LEG, LEGC, 10000, 'active']);
    assert.strictEqual((await get(`users/${LEG}`)).incentiveBalance, 10000);
    assert.strictEqual(await get(`users/${LEGC}`), undefined); // канон ҳужжат яратилмади
    assert.strictEqual((await call('claimRelativesBonus', {}, LEGC)).result, 'duplicate');
    // иккала ҳужжат: 9 хонали — 3 қариндош, канон — 3 қариндош → фақат БИТТА грант (канон ҳисобга)
    for (const p of ['x', 'y', 'z']) await relTrigger(DUAL9, p, { firstName: `Q${p}`, birthDate: bdTs(1970, 1, 10) });
    for (const p of ['u', 'v', 'w']) await relTrigger(DUAL, p, { firstName: `R${p}`, birthDate: bdTs(1971, 2, 11) });
    const grants = (await db.collection('incentive_grants').where('personKey', '==', DUAL).get()).docs;
    assert.strictEqual(grants.length, 1);
    assert.deepStrictEqual([grants[0].id, grants[0].data().uid], [`relatives_birthdays_${DUAL}`, DUAL]);
    assert.strictEqual((await get(`users/${DUAL}`)).incentiveBalance, 10000);
    assert.strictEqual((await get(`users/${DUAL9}`)).incentiveBalance, undefined);
    assert.strictEqual((await get('incentive_programs/relatives_birthdays')).counters.grantedCount, 3);
    // бузуқ id — грант йўқ
    assert.strictEqual((await api.grantRelativesBonus('12345')).code, 'UID_INVALID');
  });

  await check('C13 бонус ОДДИЙ буюртмада (байрам эмас) ва эски 9 хонали ҳисобда; бекорда тикланади', async () => {
    const ctxLeg = (d) => call('placeSupermarketOrder', { clientRequestId: rid('leg'), address: ADDR, slotId: 'morning', deliveryDate: h.addDays(todayKey, 1), ...d }, LEGC);
    const r = await ctxLeg({ items: [{ productId: 'beef_lean_1', qty: 1 }, { productId: 'soda_cola_1', qty: 3 }], origin: 'quick', useIncentive: true });
    assert.deepStrictEqual([r.grossTotal, r.incentiveApplied, r.total], [136760, 10000, 126760]);
    const o = await get(`orders/${r.orderId}`);
    assert.deepStrictEqual([o.smOrigin, o.incentiveUid, o.walletUserDocId, o.smOccasionId], ['quick', LEG, LEG, undefined]);
    assert.deepStrictEqual([(await get(`users/${LEG}`)).incentiveBalance, (await get(`users/${LEG}`)).bonusBalance], [0, 500000 - 126760]);
    assert.strictEqual((await get(`incentive_grants/relatives_birthdays_${LEGC}`)).status, 'spent');
    const ref = db.doc(`orders/${r.orderId}`);
    const before = await ref.get();
    await ref.update({ status: 'cancelled' });
    await fns.onSupermarketOrderCancelStock.run({ before, after: await ref.get() }, { params: { orderId: r.orderId } });
    assert.strictEqual((await get(`users/${LEG}`)).incentiveBalance, 10000);
    // useIncentive юборилмаса — ишлатилмайди (клиент танлови)
    const plain = await ctxLeg({ items: [{ productId: 'beef_lean_1', qty: 1 }, { productId: 'soda_cola_1', qty: 3 }] });
    assert.strictEqual(plain.incentiveApplied, undefined);
  });

  await check('C14 ўз туғилган куни: D-7..D-3 ҳар куни бошқа таклиф, opt-out, профил санаси текшируви, бир шахсга бир марта, админ матни', async () => {
    // «Мен» ёзувлари (профилдан синхронланади) → self индекс; users.birthDate — манба
    await db.doc(`users/${USER}`).update({ birthDate: '1990-07-10' });
    await relTrigger(USER, 'me', { firstName: 'Ali', isSelf: true, birthDate: bdTs(1990, 7, 10) });
    assert.deepStrictEqual((await get(`holiday_self_birthday_index/${USER}`)).md, '07-10');
    await db.doc(`users/${LEG}`).update({ birthDate: '10.7.1991' });
    await relTrigger(LEG, 'me', { firstName: 'Eski', isSelf: true, birthDate: bdTs(1991, 7, 10) });
    await db.doc(`users/${OPTOUT}`).update({ birthDate: '1990-07-10' });
    await relTrigger(OPTOUT, 'me', { firstName: 'O', isSelf: true, birthDate: bdTs(1990, 7, 10) });
    await db.doc(`users/${DUAL}`).update({ birthDate: '1980-01-15' }); // индекс 07-10 (эскирган), профил 01-15 → юборилмайди
    await relTrigger(DUAL, 'me', { firstName: 'D', isSelf: true, birthDate: bdTs(1980, 7, 10) });
    const bodies = [];
    for (const [i, dd] of ['2027-07-03', '2027-07-04', '2027-07-05', '2027-07-06', '2027-07-07'].entries()) {
      fakeNow = h.startOfKeyMs(dd) + 9 * 3600000;
      sent.length = 0;
      await api.runHolidayRemindersAll();
      const s = sent.filter((m) => m.source === 'holiday_self_birthday');
      assert.deepStrictEqual(s.map((m) => m.userId).sort(), [LEGC, USER].sort(), `${dd} ${JSON.stringify(s.map((m) => m.userId))}`);
      const days = 7 - i;
      const def = h.DEFAULT_SELF_REMINDERS.find((r) => r.daysBefore === days);
      const u = s.find((m) => m.userId === USER);
      assert.strictEqual(u.body, def.texts.uz_Latn.body);
      assert.strictEqual(s.find((m) => m.userId === LEGC).body, def.texts.ru.body);
      assert.deepStrictEqual([u.extraData.targetType, u.extraData.daysBefore, u.screen], [def.target.type, String(days), days === 6 ? 'restaurants' : 'supermarket']);
      bodies.push(u.body);
      sent.length = 0;
      await api.runHolidayRemindersAll(); // қайта ишга тушиш — такрор йўқ
      assert.strictEqual(sent.filter((m) => m.source === 'holiday_self_birthday').length, 0);
    }
    assert.strictEqual(new Set(bodies).size, 5);
    fakeNow = h.startOfKeyMs('2027-07-08') + 9 * 3600000; // D-2 — сукутда йўқ
    sent.length = 0; await api.runHolidayRemindersAll();
    assert.strictEqual(sent.filter((m) => m.source === 'holiday_self_birthday').length, 0);
    assert.ok(!(await db.collection('holiday_reminder_log').where('personKey', '==', DUAL).get()).size);
    // админ: ўз матни, D-1, бошқа мақсад; [] — ўчирилган
    const T3 = { uz_Cyrl: { title: 'Т', body: 'Туғилган кунга {days} кун' }, uz_Latn: { title: 'T', body: 'Tuğilgan kunga {days} kun' }, ru: { title: 'Т', body: 'До ДР {days} дн.' } };
    const occ = { id: 'birthday', kind: 'birthday', names: N('Туғилган кун', 'Tuğilgan kun', 'День рождения'), stage: 'internal', order: 1 };
    await expectCode(call('adminUpsertHolidayOccasion', { occasion: { ...occ, selfReminders: [{ daysBefore: 2, texts: T3, target: { type: 'cinema' } }] } }, ADMIN), 'OCCASION_INVALID');
    await call('adminUpsertHolidayOccasion', { occasion: { ...occ, selfReminders: [{ daysBefore: 1, texts: T3, target: { type: 'supermarket' } }] } }, ADMIN);
    fakeNow = h.startOfKeyMs('2027-07-09') + 9 * 3600000;
    sent.length = 0; await api.runHolidayRemindersAll();
    const s2 = sent.filter((m) => m.source === 'holiday_self_birthday');
    assert.deepStrictEqual(s2.map((m) => m.body).sort(), ['До ДР 1 дн.', 'Tuğilgan kunga 1 kun'].sort());
    await call('adminUpsertHolidayOccasion', { occasion: { ...occ, selfReminders: [] } }, ADMIN);
    fakeNow = h.startOfKeyMs('2028-07-03') + 9 * 3600000;
    sent.length = 0; await api.runHolidayRemindersAll();
    assert.strictEqual(sent.filter((m) => m.source === 'holiday_self_birthday').length, 0);
    await call('adminUpsertHolidayOccasion', { occasion: occ }, ADMIN); // сукутга қайтди
    // «Мен» ўчирилса — индекс ҳам
    await relTrigger(OPTOUT, 'me', null);
    assert.strictEqual(await get(`holiday_self_birthday_index/${OPTOUT}`), undefined);
    fakeNow = Date.now();
  });

  await check('C15 Қурбон ҳайит: Мол бозори мақсади, 10 кун олдин, супермаркет дарвозасисиз; каталогда target', async () => {
    const seed = require('../tools/data/holiday_seed_v1.json').occasions.find((o) => o.id === 'qurbon_hayit');
    await call('adminUpsertHolidayOccasion', { occasion: { ...seed, stage: 'public', dateRule: { type: 'list', dates: ['2027-05-16'] } } }, ADMIN);
    const cat = await call('getHolidayCatalog', {}, OTHER); // OTHER — супермаркет тестери эмас
    const q = cat.occasions.find((o) => o.id === 'qurbon_hayit');
    assert.deepStrictEqual([q.target, q.nextDate, q.remindDaysBefore], [{ type: 'market', market: 'livestock', categories: ['sheep_goat', 'cattle'] }, '2027-05-16', 10]);
    fakeNow = h.startOfKeyMs('2027-05-07') + 9 * 3600000; // 9 кун — ҳали эмас
    sent.length = 0; await api.runHolidayRemindersAll();
    assert.strictEqual(sent.filter((m) => m.source === 'holiday_reminder').length, 0);
    fakeNow = h.startOfKeyMs('2027-05-06') + 9 * 3600000;
    sent.length = 0; await api.runHolidayRemindersAll();
    const s = sent.filter((m) => m.source === 'holiday_reminder');
    assert.ok(s.some((m) => m.userId === OTHER), JSON.stringify(s.map((m) => m.userId)));
    assert.ok(!s.some((m) => m.userId === OPTOUT));
    const u = s.find((m) => m.userId === USER);
    assert.strictEqual(u.body, 'Qurbon hayitga 10 kun qoldi — jonliqni Mol bozoridan yaqin sotuvçilardan tanlang');
    assert.deepStrictEqual([u.screen, u.extraData.targetType, u.extraData.market, u.extraData.categories], ['market', 'market', 'livestock', 'sheep_goat,cattle']);
    assert.ok(s.find((m) => m.userId === OTHER).body.startsWith('Қурбон ҳайитга 10 кун'));
    sent.length = 0; await api.runHolidayRemindersAll();
    assert.strictEqual(sent.filter((m) => m.source === 'holiday_reminder').length, 0);
    fakeNow = Date.now();
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
