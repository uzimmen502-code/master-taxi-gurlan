/* eslint-disable no-console */
// «Автомобил суғуртаси» (эга 2026-11-28) — тоза функциялар. node test/car_insurance_pure.test.js
const assert = require('assert');
const c = require('../car_insurance');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const NOW = Date.UTC(2026, 10, 28, 6); // 2026-11-28 11:00 Тошкент
const row = (o) => ({ policyType: 'osago', regionId: '*', vehicleType: 'car', termMonths: 12, price: 200000, ...o });
const grant = (o) => ({ id: 'g1', programId: 'car_insurance_bonus', remaining: 100000, buckets: { any: 100000 }, maxOrderSharePct: 100, expiresAtMs: NOW + 86400000, ...o });

check('I1 номер калити: бўшлиқ/чизиқча/кичик ҳарф/кирилл ўхшаш — бир калит; қисқа — бўш', () => {
  assert.strictEqual(c.normalizePlate('01 a 123 bc'), '01A123BC');
  assert.strictEqual(c.normalizePlate('01-А123ВС'), '01A123BC'); // кирилл А, В, С
  assert.strictEqual(c.normalizePlate('90 777 ZZZ'), '90777ZZZ');
  assert.strictEqual(c.normalizePlate('12'), '');
  assert.strictEqual(c.normalizePlate(null), '');
});

check('I2 сана: ҳақиқий YYYY-MM-DD; кун қўшиш ой/йил чегарасида; DD.MM.YYYY кўриниш', () => {
  assert.ok(c.dateOk('2027-02-28'));
  assert.ok(!c.dateOk('2027-02-30'));
  assert.ok(!c.dateOk('28.02.2027'));
  assert.strictEqual(c.addDaysKey('2026-12-30', 4), '2027-01-03');
  assert.strictEqual(c.addDaysKey('2026-03-01', -1), '2026-02-28');
  assert.strictEqual(c.displayDate('2027-01-03'), '03.01.2027');
  assert.strictEqual(c.tashkentYear(Date.UTC(2026, 11, 31, 20)), 2027); // 01:00 Тошкент 1-январ
});

check('I3 нарх жадвали: тўғри; такрор калит, нотўғри нарх/муддат/тур — рад; float нарх рад', () => {
  assert.ok(c.validateTariffRows([row(), row({ regionId: 'xorazm', price: 180000 })]).ok);
  assert.ok(!c.validateTariffRows([row(), row()]).ok);
  assert.ok(!c.validateTariffRows([row({ price: 1000.5 })]).ok);
  assert.ok(!c.validateTariffRows([row({ price: 0 })]).ok);
  assert.ok(!c.validateTariffRows([row({ termMonths: 40 })]).ok);
  assert.ok(!c.validateTariffRows([row({ vehicleType: 'tank' })]).ok);
  assert.ok(!c.validateTariffRows([row({ policyType: 'life' })]).ok);
  assert.ok(!c.validateTariffRows([]).ok);
});

check('I4 нарх топиш: вилоят қатори устун, бўлмаса «*»; йўқ — null; танловлар рўйхати вилоятга мос', () => {
  const rows = [row(), row({ regionId: 'xorazm', price: 180000 }), row({ policyType: 'kasko', price: 900000 }), row({ termMonths: 6, price: 120000 })];
  assert.strictEqual(c.findTariffRow(rows, { policyType: 'osago', regionId: 'xorazm', vehicleType: 'car', termMonths: 12 }).price, 180000);
  assert.strictEqual(c.findTariffRow(rows, { policyType: 'osago', regionId: 'toshkent', vehicleType: 'car', termMonths: 12 }).price, 200000);
  assert.strictEqual(c.findTariffRow(rows, { policyType: 'osago', regionId: 'xorazm', vehicleType: 'bus', termMonths: 12 }), null);
  const opts = c.tariffOptionsFor(rows, 'xorazm', ['osago']);
  assert.deepStrictEqual(opts.map((o) => [o.termMonths, o.price]), [[6, 120000], [12, 180000]]);
  assert.strictEqual(c.tariffOptionsFor(rows, 'xorazm', ['osago', 'kasko']).length, 3);
});

check('I5 мой дастури: 1 → 50%, 2 → 100%, 0 → 0; нотўғри босқичлар рад', () => {
  const steps = [{ count: 1, pct: 50 }, { count: 2, pct: 100 }];
  assert.ok(c.validOilSteps(steps));
  assert.deepStrictEqual([0, 1, 2, 3].map((n) => c.oilDiscountPct(n, steps)), [0, 50, 100, 100]);
  assert.strictEqual(c.oilGoal(steps), 2);
  assert.ok(!c.validOilSteps([{ count: 2, pct: 50 }, { count: 1, pct: 100 }]));
  assert.ok(!c.validOilSteps([{ count: 1, pct: 100 }, { count: 2, pct: 50 }]));
  assert.ok(!c.validOilSteps([{ count: 1, pct: 150 }]));
});

check('I6 тўлов: 50% чегирма + бонус + ҳамён; 100% — 0 сўм; бонус улуш чегараси; маблағ етмаса sufficient=false', () => {
  const p = c.computePayment({ price: 200000, oilPct: 50, grants: [grant()], walletBalance: 0, nowMs: NOW });
  assert.deepStrictEqual([p.oilDiscount, p.afterOil, p.incentive, p.walletDue, p.sufficient], [100000, 100000, 100000, 0, true]);
  const full = c.computePayment({ price: 200000, oilPct: 100, grants: [grant()], walletBalance: 0, nowMs: NOW });
  assert.deepStrictEqual([full.oilDiscount, full.incentive, full.walletDue], [200000, 0, 0]);
  const share = c.computePayment({ price: 200000, oilPct: 0, grants: [grant({ maxOrderSharePct: 30 })], walletBalance: 140000, nowMs: NOW });
  assert.deepStrictEqual([share.incentive, share.walletDue, share.sufficient], [60000, 140000, true]);
  const odd = c.computePayment({ price: 199999, oilPct: 50, grants: [], walletBalance: 100000, nowMs: NOW });
  assert.deepStrictEqual([odd.oilDiscount, odd.walletDue, odd.sufficient], [99999, 100000, true]); // бутун сўм, floor
  const poor = c.computePayment({ price: 200000, oilPct: 0, grants: [], walletBalance: 199999, nowMs: NOW });
  assert.strictEqual(poor.sufficient, false);
});

check('I7 тўлов: супермаркет/шина туркумли грант суғуртани қопламайди; муддати ўтган грант — йўқ', () => {
  const p = c.computePayment({ price: 100000, oilPct: 0, grants: [grant({ buckets: { supermarket: 50000 } }), grant({ id: 'g2', buckets: { tire: 50000 } }), grant({ id: 'g3', expiresAtMs: NOW - 1 })], walletBalance: 100000, nowMs: NOW });
  assert.deepStrictEqual([p.incentive, p.walletDue], [0, 100000]);
  const ins = c.computePayment({ price: 100000, oilPct: 0, grants: [grant({ buckets: { insurance: 40000 } })], walletBalance: 60000, nowMs: NOW });
  assert.deepStrictEqual([ins.incentive, ins.walletDue], [40000, 60000]);
});

check('I8 ҳолат машинаси: requested→paid→in_progress→issued; рухсатсиз ўтишлар рад', () => {
  assert.ok(c.canTransition('requested', 'paid'));
  assert.ok(c.canTransition('paid', 'in_progress'));
  assert.ok(c.canTransition('in_progress', 'issued'));
  assert.ok(c.canTransition('paid', 'cancelled'));
  assert.ok(!c.canTransition('requested', 'issued'));
  assert.ok(!c.canTransition('issued', 'cancelled'));
  assert.ok(!c.canTransition('cancelled', 'paid'));
});

check('I9 эслатма кунлари: бугун+4 ва бугун+3 (Тошкент куни)', () => {
  assert.deepStrictEqual(c.reminderTargets(NOW), [{ n: 4, date: '2026-12-02' }, { n: 3, date: '2026-12-01' }]);
  assert.deepStrictEqual(c.reminderTargets(Date.UTC(2026, 11, 28, 20)).map((x) => x.date), ['2027-01-02', '2027-01-01']);
});

check('I10 кампания: OFF сукут, бонус/мой созламаси текширилади, нотаниш калит рад', () => {
  const ok = c.validateCampaign(2027, { stage: 'off', internalPhones: ['901234567'], pilotDistrictIds: [], bonusEnabled: true, bonusAmount: 100000, bonusValidityDays: 60, bonusMaxOrderSharePct: 100, bonusBudgetTotal: 10000000, oilEnabled: true, oilSteps: [{ count: 1, pct: 50 }, { count: 2, pct: 100 }] });
  assert.ok(ok.ok);
  assert.deepStrictEqual(ok.value.internalPhones, ['998901234567']);
  assert.ok(!c.validateCampaign(2027, { stage: 'off', bonusEnabled: true, bonusAmount: 0 }).ok);
  assert.ok(!c.validateCampaign(2027, { stage: 'off', oilEnabled: true, oilSteps: [] }).ok);
  assert.ok(!c.validateCampaign(2027, { stage: 'on' }).ok);
  assert.ok(!c.validateCampaign(2027, { stage: 'off', foo: 1 }).ok);
  assert.ok(!c.validateCampaign(2020, { stage: 'off' }).ok);
});

check('I11 созлама: телефонлар шахс калитига, нотўғри рад; файл тури магик байт бўйича', () => {
  const v = c.validateConfig({ stage: 'internal', internalPhones: ['+998 90 123 45 67'], agentPhones: ['901111111'], reporterPhones: [], pilotDistrictIds: ['gurlan'] });
  assert.ok(v.ok);
  assert.deepStrictEqual([v.value.internalPhones, v.value.agentPhones, v.value.kaskoEnabled, v.value.remindersEnabled], [['998901234567'], ['998901111111'], false, true]);
  assert.ok(!c.validateConfig({ stage: 'internal', agentPhones: ['123'] }).ok);
  assert.strictEqual(c.sniffFile(Buffer.from('%PDF-1.7 xxxxxxxx')).contentType, 'application/pdf');
  assert.strictEqual(c.sniffFile(Buffer.from([0xff, 0xd8, 0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0])).ext, 'jpg');
  assert.strictEqual(c.sniffFile(Buffer.from('<html>evil</html>')), null);
});

check('I12 хабарлар 3 тилда; uz_Latn янги алифбода (o\'/g\'/sh/ch йўқ)', () => {
  for (const k of Object.keys(c.NOTICE)) for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(c.NOTICE[k][l].title && c.NOTICE[k][l].body, `${k}.${l}`);
  for (const k of Object.keys(c.NOTICE)) assert.ok(!/o'|g'|sh|ch/i.test(c.NOTICE[k].uz_Latn.body + c.NOTICE[k].uz_Latn.title), k);
  for (const code of ['INSUFFICIENT_BALANCE', 'PLATE_ALREADY_ENROLLED', 'NOT_AVAILABLE']) assert.ok(!/o'|g'|sh|ch/i.test(c.messagesOf(code).uz_Latn), code);
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
