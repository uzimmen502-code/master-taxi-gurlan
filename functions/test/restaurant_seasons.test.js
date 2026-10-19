/**
 * KAFE-RESTORAN — mavsumiy bo'limlar va Ramazon jadvali: sof qoidalar (D-REST-22). Emulyatorsiz:
 *   node functions/test/restaurant_seasons.test.js
 */
'use strict';
const assert = require('assert');
const s = require('../restaurant_seasons');
const { SEASON_KEYS } = require('../restaurant_dish_index');

let pass = 0;
let failed = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log(`PASS - ${name}`); } catch (e) {
    failed += 1; console.log(`FAIL - ${name} :: ${e.message}`);
  }
}
const utc = (iso, hh = 12) => Date.parse(`${iso}T${String(hh).padStart(2, '0')}:00:00Z`);

check('parseIsoDate: faqat mavjud sana (2027-02-30, 2027-13-01, satr bo\'lmagan — null)', () => {
  assert.strictEqual(s.parseIsoDate('2027-02-08'), Date.UTC(2027, 1, 8));
  assert.strictEqual(s.parseIsoDate('2028-02-29') != null, true, 'kabisa yil');
  for (const bad of ['2027-02-30', '2027-13-01', '2027-2-8', '27-02-08', '', null, undefined, 20270208, '2027-02-08T00:00']) {
    assert.strictEqual(s.parseIsoDate(bad), null, String(bad));
  }
});

check('tashkentToday: UTC+5 (23:30 UTC — Toshkentda ertasi kun)', () => {
  assert.strictEqual(s.tashkentToday(Date.parse('2027-02-08T18:59:00Z')), '2027-02-08');
  assert.strictEqual(s.tashkentToday(Date.parse('2027-02-08T19:00:00Z')), '2027-02-09');
});

check('sanitizePeriods: to\'g\'ri davr o\'qiladi, tartiblanadi; noma\'lum kalit, teskari sana, takror, uzun davr — null', () => {
  const ok = s.sanitizePeriods([
    { key: 'qurbon', from: '2027-05-16', to: '2027-05-19', confirmed: true },
    { key: 'ramadan', from: '2027-02-08', to: '2027-03-08' },
  ]);
  assert.deepStrictEqual(ok.map((p) => p.key), ['ramadan', 'qurbon']);
  assert.deepStrictEqual(ok[0], { key: 'ramadan', from: '2027-02-08', to: '2027-03-08', confirmed: false });
  assert.strictEqual(ok[1].confirmed, true);
  const bads = [
    [{ key: 'eid', from: '2027-05-16', to: '2027-05-19' }],
    [{ key: 'ramadan', from: '2027-03-08', to: '2027-02-08' }],
    [{ key: 'ramadan', from: '2027-02-08', to: '2027-03-08' }, { key: 'ramadan', from: '2027-02-08', to: '2027-03-09' }],
    [{ key: 'wedding', from: '2027-01-01', to: '2027-12-31' }],
    [{ key: 'ramadan', from: '2027-02-30', to: '2027-03-08' }],
    'x', null, [null], Array.from({ length: 61 }, (_, i) => ({ key: 'wedding', from: `2027-01-${String((i % 28) + 1).padStart(2, '0')}`, to: `2027-01-${String((i % 28) + 1).padStart(2, '0')}` })),
  ];
  for (const b of bads) assert.strictEqual(s.sanitizePeriods(b), null, JSON.stringify(b).slice(0, 80));
  assert.deepStrictEqual(s.sanitizePeriods([]), []);
});

check('activeSeasons: sanadan 10 kun OLDIN ochiladi, 9-kunda ochiq, 11-kunda yopiq; oxirgi kun ochiq, ertasi yopiq', () => {
  const periods = [{ key: 'ramadan', from: '2027-02-08', to: '2027-03-08', confirmed: false }];
  const at = (iso) => s.activeSeasons(periods, utc(iso), 10).map((x) => x.key);
  assert.deepStrictEqual(at('2027-01-28'), [], '11 kun oldin');
  assert.deepStrictEqual(at('2027-01-29'), ['ramadan'], '10 kun oldin — ochiladi');
  assert.deepStrictEqual(at('2027-02-08'), ['ramadan']);
  assert.deepStrictEqual(at('2027-03-08'), ['ramadan'], 'oxirgi kun');
  assert.deepStrictEqual(at('2027-03-09'), [], 'tugadi');
  assert.strictEqual(s.activeSeasons(periods, utc('2027-01-29'), 10)[0].opensOn, '2027-01-29');
  assert.deepStrictEqual(s.activeSeasons(periods, utc('2027-01-31'), 0).map((x) => x.key), [], 'opensDaysBefore=0 — faqat davr ichida');
  assert.deepStrictEqual(s.activeSeasons(periods, utc('2027-02-08'), 0).map((x) => x.key), ['ramadan']);
});

check('activeSeasons: Toshkent kuni bo\'yicha (UTC 19:00 = ertasi kun); bir nechta mavsum bir vaqtda; bo\'sh/buzilgan — hech narsa', () => {
  const periods = [
    { key: 'ramadan', from: '2027-02-09', to: '2027-03-15', confirmed: true },
    { key: 'navruz', from: '2027-03-21', to: '2027-03-21', confirmed: false },
    { key: 'wedding', from: '2027-03-01', to: '2027-04-30', confirmed: true },
  ];
  assert.deepStrictEqual(s.activeSeasons(periods, Date.parse('2027-01-29T19:00:00Z'), 10).map((x) => x.key), ['ramadan'], 'Toshkentda 30 yanvar = 9 fevral − 10 kun → ochiladi');
  assert.deepStrictEqual(s.activeSeasons(periods, Date.parse('2027-01-29T18:00:00Z'), 10).map((x) => x.key), [], 'Toshkentda hali 29 yanvar');
  assert.deepStrictEqual(s.activeSeasons(periods, utc('2027-03-12'), 10).map((x) => x.key), ['ramadan', 'navruz', 'wedding'], 'SEASON_KEYS tartibida');
  assert.deepStrictEqual(s.activeSeasons(periods, utc('2027-03-05'), 10).map((x) => x.key), ['ramadan', 'wedding'], 'Navro\'z 11 martda ochiladi (21 − 10)');
  assert.deepStrictEqual(s.activeSeasons([], utc('2027-03-05')), []);
  assert.deepStrictEqual(s.activeSeasons(null, utc('2027-03-05')), []);
  assert.deepStrictEqual(s.activeSeasons([{ key: 'ramadan', from: 'x', to: 'y' }], utc('2027-03-05')), []);
});

check('hijriToGregorian / estimatePeriod: 2026 Ramazon 18 fevral (Saudiya; O\'zbekistonda 19 — admin suradi), Qurbon ~27 may', () => {
  const r = s.estimatePeriod('ramadan', 2026);
  assert.deepStrictEqual([r.from, r.confirmed], ['2026-02-18', false]);
  assert.ok(r.to >= '2026-03-17' && r.to <= '2026-03-20', `Ramazon 29–30 kun: ${r.to}`);
  const q = s.estimatePeriod('qurbon', 2026);
  assert.strictEqual(q.from, '2026-05-27');
  assert.strictEqual(q.to, '2026-05-30', '10–13 zulhijja');
  assert.deepStrictEqual(s.estimatePeriod('navruz', 2027), { key: 'navruz', from: '2027-03-21', to: '2027-03-21', confirmed: false });
  assert.deepStrictEqual(s.estimatePeriod('newyear', 2026), { key: 'newyear', from: '2026-12-31', to: '2027-01-01', confirmed: false });
  assert.strictEqual(s.estimatePeriod('wedding', 2027), null, 'to\'y mavsumi sanasi UNKNOWN — taxmin qilinmaydi');
});

check('taxminiy davrlar o\'zi sanitize\'dan o\'tadi (3 yil)', () => {
  for (const y of [2026, 2027, 2028, 2030]) {
    const { periods, added } = s.withEstimates([], [y]);
    assert.strictEqual(added.length, 4, String(y));
    assert.strictEqual(periods.length, 4);
  }
});

check('withEstimates: admin kiritgan/tasdiqlagan davrga TEGILMAYDI; yetishmayotgan yil/kalit qo\'shiladi; takroriy chaqiruv o\'zgartirmaydi', () => {
  const adminRamadan = { key: 'ramadan', from: '2027-02-09', to: '2027-03-09', confirmed: true };
  const a = s.withEstimates([adminRamadan], [2027]);
  assert.deepStrictEqual(a.periods.find((p) => p.key === 'ramadan'), adminRamadan, 'admin davri o\'zgarmadi');
  assert.deepStrictEqual(a.added.map((p) => p.key).sort(), ['navruz', 'newyear', 'qurbon']);
  const again = s.withEstimates(a.periods, [2027]);
  assert.strictEqual(again.added.length, 0);
  assert.deepStrictEqual(again.periods, a.periods);
  const next = s.withEstimates(a.periods, [2027, 2028]);
  assert.strictEqual(next.added.length, 4, 'faqat 2028 uchun');
  assert.ok(next.added.every((p) => p.from.startsWith('2028-')));
  // admin davrni 1 kunga surdi (from boshqa kun, shu yilda) — qayta taxmin qo'shilmaydi
  const shifted = s.withEstimates([{ key: 'ramadan', from: '2027-02-10', to: '2027-03-10', confirmed: false }], [2027]);
  assert.strictEqual(shifted.periods.filter((p) => p.key === 'ramadan').length, 1);
});

check('Ramazon jadvali: kunlar va hudud farqlari tekshiriladi (HH:mm, mavjud sana, -120..120)', () => {
  assert.deepStrictEqual(s.sanitizeRamadanDays({ '2027-02-09': { sahar: '05:51', iftar: '18:02' }, '2027-02-08': { sahar: '05:52', iftar: '18:01' } }), {
    '2027-02-08': { sahar: '05:52', iftar: '18:01' }, '2027-02-09': { sahar: '05:51', iftar: '18:02' },
  });
  for (const bad of [null, [], { '2027-02-30': { sahar: '05:51', iftar: '18:02' } }, { '2027-02-08': { sahar: '5:51', iftar: '18:02' } },
    { '2027-02-08': { sahar: '24:00', iftar: '18:02' } }, { '2027-02-08': { sahar: '05:51' } }, { '2027-02-08': 'x' },
    Object.fromEntries(Array.from({ length: 46 }, (_, i) => [`2027-02-${String((i % 28) + 1).padStart(2, '0')}-${i}`, { sahar: '05:00', iftar: '18:00' }]))]) {
    assert.strictEqual(s.sanitizeRamadanDays(bad), null, JSON.stringify(bad).slice(0, 60));
  }
  assert.deepStrictEqual(s.sanitizeRamadanOffsets({ nukus: 42, andijon: -11, toshkent: 0 }), { andijon: -11, nukus: 42, toshkent: 0 });
  for (const bad of [null, [], { x: 121 }, { x: -121 }, { x: 1.5 }, { x: '5' }, { 'bad key': 1 }, { '': 1 }]) {
    assert.strictEqual(s.sanitizeRamadanOffsets(bad), null, JSON.stringify(bad));
  }
});

check('ramadanTimesFor: Toshkent + farq (Nukus +42, Andijon −11); hudud/kun jadvalda yo\'q — null (taxmin yo\'q); yarim tundan o\'tishi', () => {
  const cfg = { days: { '2027-02-09': { sahar: '05:51', iftar: '18:02' }, '2027-02-10': { sahar: '00:10', iftar: '23:50' } }, offsets: { toshkent: 0, nukus: 42, andijon: -11 } };
  assert.deepStrictEqual(s.ramadanTimesFor(cfg, '2027-02-09', 'toshkent'), { sahar: '05:51', iftar: '18:02' });
  assert.deepStrictEqual(s.ramadanTimesFor(cfg, '2027-02-09', 'nukus'), { sahar: '06:33', iftar: '18:44' });
  assert.deepStrictEqual(s.ramadanTimesFor(cfg, '2027-02-09', 'andijon'), { sahar: '05:40', iftar: '17:51' });
  assert.deepStrictEqual(s.ramadanTimesFor(cfg, '2027-02-10', 'nukus'), { sahar: '00:52', iftar: '00:32' }, 'yarim tundan o\'tadi');
  assert.deepStrictEqual(s.ramadanTimesFor(cfg, '2027-02-10', 'andijon'), { sahar: '23:59', iftar: '23:39' }, 'orqaga aylanadi');
  assert.strictEqual(s.ramadanTimesFor(cfg, '2027-02-09', 'samarqand'), null, 'hudud jadvalda yo\'q');
  assert.strictEqual(s.ramadanTimesFor(cfg, '2027-02-11', 'toshkent'), null, 'kun jadvalda yo\'q');
  assert.strictEqual(s.ramadanTimesFor(cfg, '2027-02-09', ''), null);
  assert.strictEqual(s.ramadanTimesFor(cfg, '2027-02-09', undefined), null);
  assert.strictEqual(s.ramadanTimesFor(null, '2027-02-09', 'nukus'), null);
  assert.strictEqual(s.ramadanTimesFor({ days: cfg.days }, '2027-02-09', 'nukus'), null);
  assert.strictEqual(s.ramadanTimesFor(cfg, '2027-02-09', '__proto__'), null, 'prototip kalitlari');
  assert.strictEqual(s.ramadanTimesFor(cfg, '2027-02-09', 'toString'), null);
});

check('mavsum kalitlari = indeks teglari (restaurant_dish_index.SEASON_KEYS) va 5 ta', () => {
  assert.deepStrictEqual(SEASON_KEYS, ['ramadan', 'navruz', 'qurbon', 'newyear', 'wedding']);
});

console.log(`\n${pass} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
