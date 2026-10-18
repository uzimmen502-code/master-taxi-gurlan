/**
 * «Кўчмас мулк» объект сонлари созламалари — `functions/realty_settings.js`.
 *
 * Ишлатиш (functions/ ичидан):
 *   npm run test:realty-settings
 */
'use strict';
const {
  FREE_LIMIT_DEFAULT, FREE_LIMIT_MAX, FREE_LIMIT_MIN,
  freeLimitFrom, packageSizesFrom,
} = require('../realty_settings');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ── бепул лимит ──
check('созлама йўқ — бошланғич 2 (эски хатти-ҳаракат)', freeLimitFrom({}) === 2 && freeLimitFrom(null) === 2 && freeLimitFrom(undefined) === 2);
check('админ белгилаган қиймат', freeLimitFrom({realtyFreeLimit: 5}) === 5 && freeLimitFrom({realtyFreeLimit: '3'}) === 3);
check('каср яхлитланади', freeLimitFrom({realtyFreeLimit: 2.6}) === 3);
check('0 ёки манфий — камида 1 («маълумот йўқ» билан чалкашмасин)',
    freeLimitFrom({realtyFreeLimit: 0}) === FREE_LIMIT_MIN && freeLimitFrom({realtyFreeLimit: -4}) === FREE_LIMIT_MIN);
check('хато билан катта ёзилса — юқори чегарада (50)', freeLimitFrom({realtyFreeLimit: 5000}) === FREE_LIMIT_MAX);
check('матн/NaN/бўш — бошланғич',
    freeLimitFrom({realtyFreeLimit: 'abc'}) === FREE_LIMIT_DEFAULT && freeLimitFrom({realtyFreeLimit: ''}) === FREE_LIMIT_DEFAULT &&
    freeLimitFrom({realtyFreeLimit: null}) === FREE_LIMIT_DEFAULT && freeLimitFrom({realtyFreeLimit: NaN}) === FREE_LIMIT_DEFAULT);

// ── пакет ўлчамлари ──
check('созлама йўқ — [5, 10] (орқага мослик)', same(packageSizesFrom({}), [5, 10]) && same(packageSizesFrom(null), [5, 10]));
check('эски ҳужжат {5,10} — ўзгармайди', same(packageSizesFrom({realtyPackagePricing: {5: 30000, 10: 50000}}), [5, 10]));
check('админ ўлчамлари, ўсиш тартибида', same(packageSizesFrom({realtyPackagePricing: {'20': 40000, '3': 10000, '50': 80000}}), [3, 20, 50]));
check('яроқсиз калит/нарх тушиб қолади', same(packageSizesFrom({realtyPackagePricing: {'5': 100, 'x': 5, '-3': 5, '0': 5, '101': 5, '7': -1, '8': null, '9': 'abc'}}), [5]));
check('нархи 0 бўлган ўлчам (бепул пакет) қолади — қарор админники', same(packageSizesFrom({realtyPackagePricing: {'5': 0}}), [5]));
check('ҳаммаси яроқсиз/бўш — бошланғич', same(packageSizesFrom({realtyPackagePricing: {}}), [5, 10]) && same(packageSizesFrom({realtyPackagePricing: {x: 1}}), [5, 10]) && same(packageSizesFrom({realtyPackagePricing: 'oops'}), [5, 10]));
check('энг кўпи 6 та (энг кичиклари)', same(packageSizesFrom({realtyPackagePricing: Object.fromEntries([1, 2, 3, 4, 5, 6, 7, 8].map((n) => [String(n), 1000]))}), [1, 2, 3, 4, 5, 6]));
check('бошланғич массив ташқарида ўзгартирилса ҳам ичидагига таъсир қилмайди', (() => {
  const a = packageSizesFrom({}); a.push(99);
  return same(packageSizesFrom({}), [5, 10]);
})());

// ── parseCounts (админ панелдан келган қийматларни текшириш) ──
const {parseCounts, CountsError} = require('../realty_settings');
const OPTS = {maxProObjects: 200};
const okInput = () => ({
  freeLimit: 3,
  packages: [{size: 5, price: 30000}, {size: 10, price: 50000}],
  proPlans: [{id: 'pro_25', objects: 25, days: 30, price: 250000}, {id: 'pro_60', objects: 60, days: 30, price: 500000}],
});
const reasonOf = (input) => {
  try { parseCounts(input, OPTS); } catch (e) { return e instanceof CountsError ? e.reason : `OTHER:${e.message}`; }
  return null;
};
const mut = (fn) => { const x = okInput(); fn(x); return x; };

check('тўғри киришда тозаланган натижа',
    same(parseCounts(okInput(), OPTS), {
      freeLimit: 3,
      packagePricing: {5: 30000, 10: 50000},
      proPlans: [{id: 'pro_25', objects: 25, days: 30, price: 250000}, {id: 'pro_60', objects: 60, days: 30, price: 500000}],
    }));
check('бўш бепул лимит → null (бошланғичга қайтариш)',
    parseCounts(mut((x) => { x.freeLimit = ''; }), OPTS).freeLimit === null && parseCounts(mut((x) => { x.freeLimit = null; }), OPTS).freeLimit === null);
check('бепул лимит чегарадан ташқарида ёки яхлит эмас — рад',
    ['0', 51, -1, 2.5, 'abc'].every((v) => reasonOf(mut((x) => { x.freeLimit = v; })) === 'free_limit_invalid'));
check('қатор (матн) кўринишидаги рақамлар қабул қилинади', parseCounts(mut((x) => { x.freeLimit = '4'; x.packages[0].price = '30000'; }), OPTS).freeLimit === 4);
check('пакет: бўш рўйхат ва 7 тадан кўп — рад',
    reasonOf(mut((x) => { x.packages = []; })) === 'package_count_invalid' &&
    reasonOf(mut((x) => { x.packages = Array.from({length: 7}, (_, i) => ({size: i + 1, price: 1000})); })) === 'package_count_invalid');
check('пакет: яроқсиз ўлчам/нарх (манфий, каср, 101, матн) — рад',
    [{size: 0, price: 1}, {size: 101, price: 1}, {size: 5, price: -1}, {size: 5, price: 1.5}, {size: 'x', price: 1}, {size: 5}].every(
        (row) => reasonOf(mut((x) => { x.packages = [row]; })) === 'package_invalid'));
check('пакет: такрорий ўлчам — рад', reasonOf(mut((x) => { x.packages = [{size: 5, price: 1}, {size: 5, price: 2}]; })) === 'package_duplicate_size');
check('пакет: катта пакет битта объектда қиммат — рад',
    reasonOf(mut((x) => { x.packages = [{size: 5, price: 30000}, {size: 10, price: 70000}]; })) === 'package_per_object');
check('пакет: тартиб ихтиёрий киритилса ҳам ўсиш бўйича текширилади/сақланади',
    same(parseCounts(mut((x) => { x.packages = [{size: 10, price: 50000}, {size: 5, price: 30000}]; }), OPTS).packagePricing, {5: 30000, 10: 50000}));
check('пакет: бир хил объект нархи (чегара) — рухсат', reasonOf(mut((x) => { x.packages = [{size: 5, price: 25000}, {size: 10, price: 50000}]; })) === null);
check('пакет: нархи 0 (бепул пакет) — рухсат (қарор админники)', reasonOf(mut((x) => { x.packages = [{size: 5, price: 0}]; })) === null);
check('режа: яроқсиз id/объект/кун/нарх — рад',
    [{id: 'A', objects: 5, days: 5, price: 1}, {id: 'Pro 1', objects: 5, days: 5, price: 1}, {id: 'ok_id', objects: 0, days: 5, price: 1},
      {id: 'ok_id', objects: 201, days: 5, price: 1}, {id: 'ok_id', objects: 5, days: 0, price: 1}, {id: 'ok_id', objects: 5, days: 366, price: 1},
      {id: 'ok_id', objects: 5, days: 5, price: -1}, {id: 'ok_id', objects: 5.5, days: 5, price: 1}].every(
        (row) => reasonOf(mut((x) => { x.proPlans = [row]; })) === 'plan_invalid'));
check('режа: объект сони коддаги хавфсиз чегарагача (200) рухсат', reasonOf(mut((x) => { x.proPlans = [{id: 'big', objects: 200, days: 30, price: 1}]; })) === null);
check('режа: такрорий id — рад', reasonOf(mut((x) => { x.proPlans = [{id: 'a1', objects: 5, days: 5, price: 1}, {id: 'a1', objects: 6, days: 5, price: 1}]; })) === 'plan_duplicate_id');
check('режа: бўш рўйхат/7 тадан кўп — рад',
    reasonOf(mut((x) => { x.proPlans = []; })) === 'plan_count_invalid' &&
    reasonOf(mut((x) => { x.proPlans = Array.from({length: 7}, (_, i) => ({id: `p${i}x`, objects: 5, days: 5, price: 1})); })) === 'plan_count_invalid');
check('киришда рўйхатлар йўқ/бузуқ — йиқилмайди, аниқ хато',
    reasonOf({}) === 'package_count_invalid' && reasonOf(null) === 'package_count_invalid' && reasonOf({packages: 'x'}) === 'package_count_invalid');
check('хато details.index билан келади', (() => {
  try { parseCounts(mut((x) => { x.packages = [{size: 5, price: 1}, {size: 0, price: 1}]; }), OPTS); } catch (e) { return e.details.index === 1; }
  return false;
})());

const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
