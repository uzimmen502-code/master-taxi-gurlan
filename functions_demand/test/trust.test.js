/**
 * Т-18 trust va Т-10 javobgarlik shifti.
 *
 *   node functions_demand/test/trust.test.js
 *
 * Asosiy qulf: «bir marta xato qilgan odam abadiy jazolanmaydi» —
 * so'nish ishlashi va javobgarlik shiftining hujumga yopiqligi.
 */
const assert = require('assert');
const t = require('../trust/compute');
const { DEFAULTS } = require('../core/config');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const cfg = DEFAULTS;
const now = new Date('2026-10-03T12:00:00Z');
const DAY = 24 * 3600 * 1000;

function daysAgo(n) {
  return new Date(now.getTime() - n * DAY);
}

console.log('decayFactor');
ok('yangi voqea -> 1.0', () => {
  assert.strictEqual(t.decayFactor(daysAgo(1).getTime(), now.getTime(), cfg.trust.decay), 1);
});
ok('100 kunlik voqea -> 0.5', () => {
  assert.strictEqual(t.decayFactor(daysAgo(100).getTime(), now.getTime(), cfg.trust.decay), 0.5);
});
ok('200 kunlik voqea -> 0.25', () => {
  assert.strictEqual(t.decayFactor(daysAgo(200).getTime(), now.getTime(), cfg.trust.decay), 0.25);
});
ok('chegarada (90 kun) hali to`liq', () => {
  assert.strictEqual(t.decayFactor(daysAgo(89).getTime(), now.getTime(), cfg.trust.decay), 1);
});

console.log('computeTrust');
ok('voqeasiz -> boshlang`ich 50', () => {
  const r = t.computeTrust([], cfg, now);
  assert.strictEqual(r.score, 50);
});
ok('10 ta bajarilgan buyurtma -> 70', () => {
  const events = Array.from({ length: 10 }, () => ({ type: t.EVENT.COMPLETED, at: daysAgo(5) }));
  assert.strictEqual(t.computeTrust(events, cfg, now).score, 70);
});
ok('no-show eng kuchli ta`sir', () => {
  const r = t.computeTrust([{ type: t.EVENT.NO_SHOW, at: daysAgo(1) }], cfg, now);
  assert.strictEqual(r.score, 35);
});
ok('tasdiqlangan shikoyat -20', () => {
  const r = t.computeTrust([{ type: t.EVENT.CONFIRMED_COMPLAINT, at: daysAgo(1) }], cfg, now);
  assert.strictEqual(r.score, 30);
});
ok('ASOSIY QULF: bir marta xato abadiy jazolanmaydi', () => {
  // Yangi no-show: 50 - 15 = 35 (1-to'lqinga kirmaydi)
  const yangi = t.computeTrust([{ type: t.EVENT.NO_SHOW, at: daysAgo(1) }], cfg, now);
  assert.strictEqual(t.allowedInFirstWave(yangi.score, cfg), false);
  // 200 kundan keyin: 50 - 15*0.25 = 46.25 -> 46 (qaytadan kiradi)
  const eski = t.computeTrust([{ type: t.EVENT.NO_SHOW, at: daysAgo(200) }], cfg, now);
  assert.strictEqual(eski.score, 46);
  assert.strictEqual(t.allowedInFirstWave(eski.score, cfg), true);
});
ok('0..100 chegarasidan chiqmaydi', () => {
  const kop = Array.from({ length: 50 }, () => ({ type: t.EVENT.COMPLETED, at: daysAgo(1) }));
  assert.strictEqual(t.computeTrust(kop, cfg, now).score, 100);
  const yomon = Array.from({ length: 50 }, () => ({ type: t.EVENT.NO_SHOW, at: daysAgo(1) }));
  assert.strictEqual(t.computeTrust(yomon, cfg, now).score, 0);
});
ok('kelajakdagi voqea hisobga olinmaydi', () => {
  // Soat buzilgan qurilma trust`ni «abadiy yangi» qilib qo`ymasligi kerak.
  const kelajak = new Date(now.getTime() + 10 * DAY);
  const r = t.computeTrust([
    { type: t.EVENT.NO_SHOW, at: kelajak },
    { type: t.EVENT.COMPLETED, at: daysAgo(1) },
  ], cfg, now);
  assert.strictEqual(r.counted, 1);
  assert.strictEqual(r.ignored, 1);
  assert.strictEqual(r.score, 52);
});
ok('sanasi yo`q voqea o`tkazib yuboriladi', () => {
  const r = t.computeTrust([{ type: t.EVENT.COMPLETED, at: null }], cfg, now);
  assert.strictEqual(r.counted, 0);
  assert.strictEqual(r.score, 50);
});
ok('noma`lum tur o`tkazib yuboriladi (jimgina buzmaydi)', () => {
  const r = t.computeTrust([{ type: 'xayoliy_voqea', at: daysAgo(1) }], cfg, now);
  assert.strictEqual(r.ignored, 1);
  assert.strictEqual(r.score, 50);
});
ok('hujjatdagi `weight` konfigdan ustun (qo`lda tuzatish uchun)', () => {
  const r = t.computeTrust([{ type: t.EVENT.COMPLETED, at: daysAgo(1), weight: 10 }], cfg, now);
  assert.strictEqual(r.score, 60);
});
ok('haridor tomoni: talabni tashlab ketish -3', () => {
  const r = t.computeTrust([{ type: t.EVENT.DEMAND_ABANDONED, at: daysAgo(1) }], cfg, now);
  assert.strictEqual(r.score, 47);
});
ok('jurnal o`zgarmas -> qayta hisoblash bir xil natija', () => {
  const events = [
    { type: t.EVENT.COMPLETED, at: daysAgo(10) },
    { type: t.EVENT.LATE_CANCEL, at: daysAgo(100) },
    { type: t.EVENT.RATING_5, at: daysAgo(3) },
  ];
  const a = t.computeTrust(events, cfg, now);
  const b = t.computeTrust(events, cfg, now);
  assert.deepStrictEqual(a, b);
});

console.log('chegaralar');
ok('trust 40 -> 1-to`lqinga kiradi', () => {
  assert.strictEqual(t.allowedInFirstWave(40, cfg), true);
  assert.strictEqual(t.allowedInFirstWave(39, cfg), false);
});
ok('trust 20 dan past -> matching`dan chiqariladi', () => {
  assert.strictEqual(t.excludedFromMatching(19, cfg), true);
  assert.strictEqual(t.excludedFromMatching(20, cfg), false);
});

console.log('Т-10 — javobgarlik shifti (HUJUMGA YOPIQ)');
ok('tasdiqlanmagan kuryer -> 300 ming', () => {
  assert.strictEqual(t.liabilityCap({ trustScore: 50 }, cfg), 300000);
});
ok('pasporti tasdiqlangan -> 1 mln', () => {
  assert.strictEqual(
    t.liabilityCap({ trustScore: 50, passportVerified: true }, cfg),
    1000000,
  );
});
ok('to`liq tasdiqlangan + 20 buyurtma -> 3 mln', () => {
  assert.strictEqual(
    t.liabilityCap({
      trustScore: 70, passportVerified: true,
      selfEmploymentVerified: true, completedCount: 20,
    }, cfg),
    3000000,
  );
});
ok('20 buyurtmadan kam -> 1 mln', () => {
  assert.strictEqual(
    t.liabilityCap({
      trustScore: 70, passportVerified: true,
      selfEmploymentVerified: true, completedCount: 19,
    }, cfg),
    1000000,
  );
});
ok('trust past bo`lsa pasport ham yordam bermaydi', () => {
  // Himoya: ishonchsiz kuryer qimmat posilka olmasligi kerak.
  assert.strictEqual(
    t.liabilityCap({ trustScore: 25, passportVerified: true, selfEmploymentVerified: true, completedCount: 50 }, cfg),
    300000,
  );
});
ok('50 mln deb yozilgan posilka hech kimga tushmaydi', () => {
  // KONSEPSIYADAGI TESHIK: yuboruvchi istalgan raqam yozib, kuryerdan
  // cheklanmagan pul talab qilishi mumkin edi.
  const engYaxshi = {
    trustScore: 100, passportVerified: true,
    selfEmploymentVerified: true, completedCount: 500,
  };
  assert.strictEqual(t.canCarryDeclaredValue(50000000, engYaxshi, cfg), false);
  assert.strictEqual(t.canCarryDeclaredValue(3000000, engYaxshi, cfg), true);
  assert.strictEqual(t.canCarryDeclaredValue(3000001, engYaxshi, cfg), false);
});
ok('qiymat ko`rsatilmasa (0) hamma olishi mumkin', () => {
  assert.strictEqual(t.canCarryDeclaredValue(0, { trustScore: 50 }, cfg), true);
  assert.strictEqual(t.canCarryDeclaredValue(null, { trustScore: 50 }, cfg), true);
});
ok('provider yo`q -> eng past shift', () => {
  assert.strictEqual(t.liabilityCap(null, cfg), 300000);
  assert.strictEqual(t.liabilityCap(undefined, cfg), 300000);
});

console.log(`\n${passed} test o'tdi.`);
