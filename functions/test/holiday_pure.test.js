/**
 * Байрам саватчаси — тоза функциялар (эга 2026-11-26).  node test/holiday_pure.test.js
 */
'use strict';
const assert = require('assert');
const h = require('../holiday');
const sm = require('../supermarket');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
const N = { uz_Cyrl: 'А', uz_Latn: 'A', ru: 'А' };
const tashMs = (key, hh = 9) => h.startOfKeyMs(key) + hh * 3600000;
const can = (d) => (d.length === 9 ? `998${d}` : d);

check('P1 сана: Тошкент калити, кабиса, addDays/daysBetween', () => {
  assert.strictEqual(h.dateKeyOf(Date.UTC(2026, 10, 25, 19, 30)), '2026-11-26'); // UTC 19:30 = Тошкент 00:30
  assert.ok(h.validDateKey('2028-02-29')); assert.ok(!h.validDateKey('2027-02-29')); assert.ok(!h.validDateKey('2027-13-01'));
  assert.strictEqual(h.addDays('2026-12-28', 5), '2027-01-02');
  assert.strictEqual(h.daysBetween('2026-12-22', '2027-01-01'), 10);
});

check('P2 туғилган сана: клиент маҳаллий ярим туни (UTC олдинги кун 19:00) → тўғри MM-DD', () => {
  assert.strictEqual(h.mdOfBirth({ toMillis: () => Date.UTC(1990, 2, 7, 19, 0) }), '03-08');
  assert.strictEqual(h.mdOfBirth(null), null);
  assert.strictEqual(h.mdOfBirth('1990-03-08'), null);
});

check('P3 туғилган кун нишони: today+5; 29-февраль кабиса бўлмаган йилда 28-февралда', () => {
  assert.deepStrictEqual(h.birthdayMdTargets('2026-11-26', 5), { target: '2026-12-01', mds: ['12-01'] });
  assert.deepStrictEqual(h.birthdayMdTargets('2027-02-23', 5), { target: '2027-02-28', mds: ['02-28', '02-29'] });
  assert.deepStrictEqual(h.birthdayMdTargets('2028-02-23', 5), { target: '2028-02-28', mds: ['02-28'] });
});

check('P4 байрам санаси: fixed (йил ўтиши), list (ой тақвими, админ рўйхати), бўш рўйхат — null', () => {
  const ny = { kind: 'holiday', bigHoliday: true, dateRule: { type: 'fixed', md: '01-01' } };
  assert.strictEqual(h.occasionNextDate(ny, '2026-11-26'), '2027-01-01');
  assert.strictEqual(h.occasionNextDate(ny, '2027-01-01'), '2027-01-01');
  const hayit = { kind: 'holiday', dateRule: { type: 'list', dates: ['2028-02-27', '2027-03-10', '2026-03-20'] } };
  assert.strictEqual(h.occasionNextDate(hayit, '2026-11-26'), '2027-03-10');
  assert.strictEqual(h.occasionNextDate(hayit, '2027-03-11'), '2028-02-27');
  assert.strictEqual(h.occasionNextDate(hayit, '2028-03-01'), null);
  assert.strictEqual(h.occasionNextDate({ kind: 'holiday', dateRule: { type: 'list', dates: [] } }, '2026-11-26'), null);
});

check('P5 эслатма куни: оддий 5, катта 10 (сукут), админ қиймати устун; due фақат аниқ кунда', () => {
  assert.strictEqual(h.remindDaysOf({ kind: 'birthday' }), 5);
  assert.strictEqual(h.remindDaysOf({ kind: 'holiday', bigHoliday: true }), 10);
  assert.strictEqual(h.remindDaysOf({ kind: 'holiday', bigHoliday: true, remindDaysBefore: 7 }), 7);
  const ny = { kind: 'holiday', bigHoliday: true, dateRule: { type: 'fixed', md: '01-01' } };
  assert.deepStrictEqual(h.holidayDue(ny, '2026-12-22'), { due: true, date: '2027-01-01', days: 10 });
  assert.strictEqual(h.holidayDue(ny, '2026-12-21').due, false);
  assert.strictEqual(h.holidayDue(ny, '2026-12-23').due, false);
  const nav = { kind: 'holiday', dateRule: { type: 'fixed', md: '03-21' } };
  assert.strictEqual(h.holidayDue(nav, '2027-03-16').due, true);
});

check('P6 validateOccasion: тўғри/хато (birthday dateRule тақиқ, 02-29 fixed тақиқ, такрор сана, номаълум калит)', () => {
  const ok = { id: 'navruz', names: N, kind: 'holiday', dateRule: { type: 'fixed', md: '03-21' }, stage: 'off', order: 2 };
  assert.ok(h.validateOccasion(ok).ok);
  assert.ok(h.validateOccasion({ id: 'birthday', names: N, kind: 'birthday', stage: 'internal', order: 1 }).ok);
  const errs = (o) => h.validateOccasion(o).errors.join('|');
  assert.match(errs({ ...ok, kind: 'birthday' }), /DATE_RULE_FORBIDDEN/);
  assert.match(errs({ ...ok, dateRule: { type: 'fixed', md: '02-29' } }), /MD_INVALID/);
  assert.match(errs({ ...ok, dateRule: { type: 'list', dates: ['2027-03-10', '2027-03-10'] } }), /DATE_DUPLICATE/);
  assert.match(errs({ ...ok, stage: 'live' }), /STAGE_INVALID/);
  assert.match(errs({ ...ok, extra: 1 }), /UNKNOWN_KEY extra/);
  assert.match(errs({ ...ok, names: { uz_Cyrl: 'А' } }), /NAME_MISSING names.uz_Latn/);
  assert.match(errs({ ...ok, remindDaysBefore: 0 }), /REMIND_INVALID/);
  const n = h.normalizeOccasion({ ...ok, bigHoliday: true });
  assert.strictEqual(n.remindDaysBefore, 10);
});

const BASKET = {
  id: 'bd_simple', occasionId: 'birthday', tier: 'simple', names: N, baseGuests: 10, active: true,
  items: [
    { groupId: 'beef', qty: 2, varietyId: 'lean', priority: 1 },
    { groupId: 'soda', qty: 4, priority: 5 },
    { groupId: 'ice_cream', qtyPerGuest: 1, qty: 10, priority: 7 },
  ],
};
check('P7 validateBasket: таксономия гуруҳи, такрор гуруҳ, qty/priority', () => {
  const groups = { beef: true, soda: true, ice_cream: true };
  assert.ok(h.validateBasket(BASKET, groups).ok);
  assert.match(h.validateBasket(BASKET, { beef: true }).errors.join('|'), /GROUP_UNKNOWN items\[1\]/);
  const dup = { ...BASKET, items: [...BASKET.items, { groupId: 'beef', qty: 1 }] };
  assert.match(h.validateBasket(dup, groups).errors.join('|'), /GROUP_DUPLICATE/);
  assert.match(h.validateBasket({ ...BASKET, items: [{ groupId: 'beef', qty: 0 }] }, groups).errors.join('|'), /QTY_INVALID/);
  assert.match(h.validateBasket({ ...BASKET, items: [{ groupId: 'beef', qty: 1, priority: 10 }] }, groups).errors.join('|'), /PRIORITY_INVALID/);
  assert.match(h.validateBasket({ ...BASKET, tier: 'xl' }, groups).errors.join('|'), /TIER_INVALID/);
});

const GROUPS = {
  beef: { id: 'beef', unit: 'kg', step: 0.5 }, soda: { id: 'soda', unit: 'piece', step: 1 }, ice_cream: { id: 'ice_cream', unit: 'piece', step: 1 },
};
const off = (id, g, price, extra = {}) => ({ id, smGroupId: g, price, stock: 100, smStatus: 'active', unit: GROUPS[g].unit, qtyStep: GROUPS[g].step, ...extra });
const OFFERS = [
  off('beef_lean_1', 'beef', 90000, { smVariety: { id: 'lean' } }),
  off('beef_lean_2', 'beef', 85000, { smVariety: { id: 'lean' } }),
  off('beef_bone_1', 'beef', 60000, { smVariety: { id: 'bone' } }),
  off('soda_cola_1', 'soda', 12000), off('soda_fanta_1', 'soda', 11000),
  off('icecream_1_', 'ice_cream', 5000),
  off('beef_hidden', 'beef', 1000, { smStatus: 'hidden' }),
];
check('P8 ақлли сават: нав ичида энг арзон, гуруҳда энг арзон, qtyPerGuest, сони бўйича масштаб + qtyStep га юқорига', () => {
  const r = h.buildBasketPure({ basket: BASKET, groups: GROUPS, offers: OFFERS, guests: null, budget: null, feeBp: 0 });
  assert.deepStrictEqual(r.lines.map((l) => [l.productId, l.qty, l.total]), [['beef_lean_2', 2, 170000], ['soda_fanta_1', 4, 44000], ['icecream_1_', 10, 50000]]);
  assert.strictEqual(r.goods, 264000); assert.strictEqual(r.total, 264000); assert.deepStrictEqual(r.changes, []);
  const r7 = h.buildBasketPure({ basket: BASKET, groups: GROUPS, offers: OFFERS, guests: 7, budget: null, feeBp: 1100 });
  // beef 2×7/10=1.4 → 1.5 кг (қадам 0.5); soda 4×7/10=2.8 → 3; ice cream 1×7
  assert.deepStrictEqual(r7.lines.map((l) => l.qty), [1.5, 3, 7]);
  assert.strictEqual(r7.goods, 127500 + 33000 + 35000);
  assert.strictEqual(r7.fee, sm.feeOf(r7.goods, 1100));
  assert.strictEqual(r7.guests, 7);
});

check('P9 бюджет: аввал алмаштириш (энг катта тежам), кейин паст устуворликни олиб ташлаш; ҳар ўзгариш қайтади', () => {
  const r = h.buildBasketPure({ basket: BASKET, groups: GROUPS, offers: OFFERS, guests: null, budget: 200000, feeBp: 0 });
  assert.strictEqual(r.changes[0].type, 'swap'); assert.strictEqual(r.changes[0].toOfferId, 'beef_bone_1'); assert.strictEqual(r.changes[0].saving, 50000);
  // 120000 + 44000 + 50000 = 214000 > 200000 → ice_cream (priority 7) олинади
  assert.deepStrictEqual(r.changes[1], { type: 'drop', reason: 'budget', groupId: 'ice_cream', offerId: 'icecream_1_', saving: 50000 });
  assert.strictEqual(r.total, 164000); assert.strictEqual(r.withinBudget, true);
  const tight = h.buildBasketPure({ basket: BASKET, groups: GROUPS, offers: OFFERS, guests: null, budget: 1000, feeBp: 0 });
  assert.strictEqual(tight.lines.length, 0); assert.strictEqual(tight.withinBudget, true);
  const fits = h.buildBasketPure({ basket: BASKET, groups: GROUPS, offers: OFFERS, guests: null, budget: 264000, feeBp: 0 });
  assert.deepStrictEqual(fits.changes, []); // чегара: айнан бюджет — ўзгармайди
});

check('P10 мавжуд эмас: таклиф йўқ/stock етмайди/бошқа бирлик → unavailable; нав йўқ → swap(unavailable)', () => {
  const offers = [off('beef_bone_1', 'beef', 60000, { smVariety: { id: 'bone' } }), off('soda_x_0001', 'soda', 1000, { stock: 2 }), off('ice_kg_0001', 'ice_cream', 1, { unit: 'kg' })];
  const r = h.buildBasketPure({ basket: BASKET, groups: GROUPS, offers, guests: null, budget: null, feeBp: 0 });
  assert.deepStrictEqual(r.changes.map((c) => [c.type, c.groupId, c.reason || '']), [['swap', 'beef', 'unavailable'], ['unavailable', 'soda', ''], ['unavailable', 'ice_cream', '']]);
  assert.strictEqual(r.lines.length, 1);
});

check('P11 совға: тўғри, телефон канон, хабар ≤200, hidePrice доим true, хато шакллар', () => {
  assert.deepStrictEqual(h.parseGift({ recipientName: ' Онам ', recipientPhone: '+998 90 123-45-67', message: 'Табриклайман' }, can),
    { gift: { recipientName: 'Онам', recipientPhone: '998901234567', message: 'Табриклайман', hidePrice: true } });
  assert.deepStrictEqual(h.parseGift(null, can), { gift: null });
  assert.strictEqual(h.parseGift({ recipientName: '', recipientPhone: '901234567' }, can).code, 'INVALID_REQUEST');
  assert.strictEqual(h.parseGift({ recipientName: 'A', recipientPhone: '123' }, can).code, 'INVALID_REQUEST');
  assert.strictEqual(h.parseGift({ recipientName: 'A', recipientPhone: '901234567', message: 'x'.repeat(201) }, can).code, 'INVALID_REQUEST');
  assert.ok(h.parseGift({ recipientName: 'A', recipientPhone: '901234567', message: 'x'.repeat(200) }, can).gift);
  assert.strictEqual(h.parseGift({ recipientName: 'A', recipientPhone: '901234567', hidePrice: false }, can).code, 'INVALID_REQUEST');
  assert.strictEqual(h.parseGift({ recipientName: 'A', recipientPhone: '901234567', price: 1 }, can).code, 'INVALID_REQUEST');
});

check('P12 sana оралиқлари: бугун cutoff, эртага ва +14 — ҳамма, +15/ўтган — йўқ', () => {
  const settings = { cutoffMin: 60, slots: [{ id: 'morning', names: N, startMin: 600, endMin: 780 }, { id: 'evening', names: N, startMin: 1080, endMin: 1260 }] };
  const now = tashMs('2026-11-26', 12); // 12:00 Тошкент
  assert.deepStrictEqual(h.slotsForDate(settings, now, '2026-11-26').map((s) => s.id), ['evening']);
  assert.deepStrictEqual(h.slotsForDate(settings, now, '2026-11-27').map((s) => s.id), ['morning', 'evening']);
  assert.strictEqual(h.slotsForDate(settings, now, '2026-12-10')[0].date, '2026-12-10');
  assert.deepStrictEqual(h.slotsForDate(settings, now, '2026-12-11'), []);
  assert.deepStrictEqual(h.slotsForDate(settings, now, '2026-11-25'), []);
  assert.deepStrictEqual(h.slotsForDate(settings, now, 'bad'), []);
});

check('P13 совға PII: якунлангандан 7 кун кейин redact; эрта — кўчириш; фаол — эртага', () => {
  const now = Date.UTC(2026, 11, 20);
  const day = 86400000;
  assert.deepStrictEqual(h.giftPurgeDecision({ status: 'new' }, now), { action: 'reschedule', nextMs: now + day });
  assert.deepStrictEqual(h.giftPurgeDecision({ status: 'delivered', deliveredAt: { toMillis: () => now - 8 * day } }, now), { action: 'redact' });
  assert.deepStrictEqual(h.giftPurgeDecision({ status: 'delivered', deliveredAt: { toMillis: () => now - 7 * day } }, now), { action: 'redact' });
  assert.deepStrictEqual(h.giftPurgeDecision({ fulfillmentStatus: 'completed', statusUpdatedAt: { toMillis: () => now - 2 * day } }, now), { action: 'reschedule', nextMs: now + 5 * day });
  assert.deepStrictEqual(h.giftPurgeDecision({ status: 'cancelled', statusUpdatedAt: { toMillis: () => now - 10 * day } }, now), { action: 'redact' });
});

check('P14 қариндошлар бонуси: яроқли қариндош, дастур текшируви, босқич, супермаркет грантлари', () => {
  const ts = { toMillis: () => Date.UTC(1990, 2, 7, 19) };
  assert.ok(h.relativeEligible({ firstName: 'Лола', birthDate: ts }));
  assert.ok(h.relativeEligible({ fullName: 'Каримов Ali', birthDate: ts }));
  assert.ok(!h.relativeEligible({ firstName: 'Мен', birthDate: ts, isSelf: true }));
  assert.ok(!h.relativeEligible({ firstName: 'Лола' }));
  assert.ok(!h.relativeEligible({ firstName: ' ', birthDate: ts }));
  const P = { title: N, stage: 'off', internalPhones: [], pilotDistrictIds: [], amount: 10000, minRelatives: 3, minOrderAmount: 100000, maxOrderSharePct: 100, validityDays: 30, budgetTotal: 1000000 };
  assert.ok(h.validateBonusProgram(P).ok);
  assert.match(h.validateBonusProgram({ ...P, amount: 10000.5 }).errors.join('|'), /AMOUNT_INVALID/);
  assert.match(h.validateBonusProgram({ ...P, budgetTotal: 5000 }).errors.join('|'), /BUDGET_INVALID/);
  assert.ok(!h.bonusStageAllows(P, '998901234567', 'gurlan'));
  assert.ok(h.bonusStageAllows({ ...P, stage: 'internal', internalPhones: ['998901234567'] }, '998901234567', ''));
  assert.ok(!h.bonusStageAllows({ ...P, stage: 'internal', internalPhones: ['998901234567'] }, '998900000000', ''));
  assert.ok(h.bonusStageAllows({ ...P, stage: 'pilot', pilotDistrictIds: ['gurlan'] }, '998900000000', 'gurlan'));
  assert.ok(h.bonusStageAllows({ ...P, stage: 'public' }, '998900000000', ''));
  const doc = (id, data) => ({ id, ref: { id }, data: () => data });
  const exp = { toMillis: () => Date.now() + 86400000 };
  const g = h.supermarketGrants([
    doc('relatives_birthdays_1', { uid: '1', programId: 'relatives_birthdays', remaining: 10000, buckets: { supermarket: 10000 }, minOrderAmount: 100000, maxOrderSharePct: 100, expiresAt: exp, status: 'active' }),
    doc('women_100k_1', { uid: '1', programId: 'women_100k', remaining: 100000, buckets: { any: 100000 }, maxOrderSharePct: 50, expiresAt: exp, status: 'active' }),
  ], 120000);
  assert.deepStrictEqual(g.map((x) => x.id), ['relatives_birthdays_1']); // аёллар гранти супермаркетга КИРМАЙДИ
  assert.strictEqual(h.supermarketGrants([doc('r', { buckets: { supermarket: 10000 }, minOrderAmount: 100000 })], 99999).length, 0); // min order
  assert.strictEqual(h.supermarketGrants([doc('r', { buckets: { supermarket: 10000 }, minOrderAmount: 100000 })], 100000).length, 1);
});

check('P15 sm_lists: ихтиёрий occasionId (тўғри/хато), эски рўйхат ўзгармайди', () => {
  const base = { name: 'Туғилган кун', items: [{ groupId: 'beef', qty: 1 }], remind: { enabled: false, weekday: 1, minute: 600 } };
  assert.strictEqual(sm.listShapeProblem(base), '');
  assert.strictEqual(sm.listShapeProblem({ ...base, occasionId: 'birthday' }), '');
  assert.strictEqual(sm.listShapeProblem({ ...base, occasionId: 'Bad-Id' }), 'OCCASION_INVALID');
  assert.ok(sm.ORDER_ORIGINS.includes('holiday'));
});

check('P16 3 тил матнлари: ҳар тилда title/body, жойлагичлар', () => {
  for (const T of [h.BIRTHDAY_TEXT, h.HOLIDAY_TEXT, h.GIFT_TEXT, h.BONUS_TEXT]) {
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) { assert.ok(T[l].title && T[l].body, l); }
  }
  assert.ok(h.BIRTHDAY_TEXT.uz_Cyrl.body.includes('{name}') && h.BIRTHDAY_TEXT.ru.body.includes('{days}'));
  assert.ok(!/[ʻʼ‘’]|o'|g'|sh|ch/i.test(h.BIRTHDAY_TEXT.uz_Latn.body.replace('{name}', '').replace(/savat|kun|qoldi/g, ''))); // янги лотин: ş/ç/ğ/ö
  assert.ok(!/\d/.test(h.GIFT_TEXT.ru.body.replace('{date}', ''))); // нарх йўқ
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
