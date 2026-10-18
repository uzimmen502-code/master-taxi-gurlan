/**
 * «Кўчмас мулк» СОФ ҳимоя мантиқи — `functions/realty_guards.js`.
 *
 * Ишлатиш (functions/ ичидан):
 *   npm run test:realty-guards
 */
'use strict';
const {
  isValidIdemKey, idemDocId, idemMatches, storageBucketsFor,
  isOwnAdsImageUrl, checkImageUrls, countActiveFromDocs,
} = require('../realty_guards');

const results = [];
function check(name, pass) {
  results.push({name, pass});
  console.log(`${pass ? '  ok  ' : ' FAIL '} ${name}`);
}

const canon = (v) => {
  const d = String(v || '').replace(/\D/g, '');
  return d.length === 9 ? `998${d}` : d;
};
const UID = '998901234567';
const BUCKETS = storageBucketsFor('master-taxi-gurlan', '');
const url = (path, {bucket = 'master-taxi-gurlan.firebasestorage.app', host = 'firebasestorage.googleapis.com', proto = 'https'} = {}) =>
  `${proto}://${host}/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=abc`;

// ── идемпотентлик калити ──
check('uuid калит яроқли', isValidIdemKey('3f2b8a52-5c1e-4c7e-9a3b-0d1f2e3a4b5c'));
check('қисқа калит ҳам яроқли (ҳужжат ID фойдаланувчига боғланган)', isValidIdemKey('i1'));
check('бўш/ўта узун/махсус белгили/йўл белгили калит яроқсиз',
    !isValidIdemKey('') && !isValidIdemKey('a'.repeat(65)) &&
    !isValidIdemKey('abcd efgh') && !isValidIdemKey('../../etc/passwd') &&
    !isValidIdemKey('a/b') && !isValidIdemKey(null) && !isValidIdemKey(undefined));
check('ҳужжат ID фойдаланувчига боғланган',
    idemDocId('realty_pkg', UID, 'k1') !== idemDocId('realty_pkg', '998907778899', 'k1'));
check('idemMatches: ўша фойдаланувчи ва ўша сўров',
    idemMatches({uid: UID, fp: 'size:5'}, UID, 'size:5') === true);
check('idemMatches: бошқа фойдаланувчи — йўқ',
    idemMatches({uid: UID, fp: 'size:5'}, '998907778899', 'size:5') === false);
check('idemMatches: бошқа ўлчам — йўқ',
    idemMatches({uid: UID, fp: 'size:5'}, UID, 'size:10') === false);
check('idemMatches: uid/fp сақланмаган эски ёзув — йўқ (жимгина қайтарилмайди)',
    idemMatches({result: {ok: true}}, UID, 'size:5') === false && idemMatches(null, UID, 'x') === false);

// ── расм URL'лари ──
check('ўз ads/{uid}/ расми яроқли', isOwnAdsImageUrl(url(`ads/${UID}/1_a.jpg`), UID, canon, BUCKETS));
check('+998 / 998 фарқи йўқ (каноник)', isOwnAdsImageUrl(url('ads/+998901234567/1_a.jpg'), UID, canon, BUCKETS));
check('бошқа эганинг папкаси — йўқ', !isOwnAdsImageUrl(url('ads/998907778899/1_a.jpg'), UID, canon, BUCKETS));
check('бошқа йўл (tv_clips/…) — йўқ', !isOwnAdsImageUrl(url(`tv_clips/${UID}/a.jpg`), UID, canon, BUCKETS));
check('бошқа сайт — йўқ', !isOwnAdsImageUrl('https://evil.example/pic.jpg', UID, canon, BUCKETS));
check('бошқа хост (firebasestorage ўхшаш) — йўқ',
    !isOwnAdsImageUrl(url(`ads/${UID}/a.jpg`, {host: 'firebasestorage.googleapis.com.evil.io'}), UID, canon, BUCKETS));
check('http (ҳимоясиз) — йўқ', !isOwnAdsImageUrl(url(`ads/${UID}/a.jpg`, {proto: 'http'}), UID, canon, BUCKETS));
check('бегона bucket — йўқ', !isOwnAdsImageUrl(url(`ads/${UID}/a.jpg`, {bucket: 'attacker-bucket'}), UID, canon, BUCKETS));
check('bucket созламаси йўқ бўлса — фақат хост ва йўл текширилади',
    isOwnAdsImageUrl(url(`ads/${UID}/a.jpg`, {bucket: 'any'}), UID, canon, []));
check('ads/{uid} ўзи (файлсиз) ва нотўғри URL — йўқ',
    !isOwnAdsImageUrl(url(`ads/${UID}`), UID, canon, BUCKETS) && !isOwnAdsImageUrl('not a url', UID, canon, BUCKETS) &&
    !isOwnAdsImageUrl('', UID, canon, BUCKETS));
check('бузилган %-кодлаш йиқитмайди',
    !isOwnAdsImageUrl(`https://firebasestorage.googleapis.com/v0/b/${BUCKETS[0]}/o/ads%2F%E0%A4%A`, UID, canon, BUCKETS));

// ── рўйхат ──
const own = (n) => url(`ads/${UID}/${n}.jpg`);
check('checkImageUrls: ўзиники қабул, такрор олиб ташланади, 5 тагача',
    JSON.stringify(checkImageUrls([own(1), own(1), own(2), own(3), own(4), own(5), own(6)], {uid: UID, canon, buckets: BUCKETS}).urls) ===
    JSON.stringify([own(1), own(2), own(3), own(4), own(5)]));
check('checkImageUrls: биттаси бегона бўлса — бутун рўйхат рад (invalid)',
    !!checkImageUrls([own(1), 'https://evil.example/x.jpg'], {uid: UID, canon, buckets: BUCKETS}).invalid);
const legacy = 'https://old.example/legacy.jpg';
check('таҳрир: эълонда аллақачон турган эски URL ўз ҳолича қолади (орқага мослик)',
    JSON.stringify(checkImageUrls([legacy, own(1)], {uid: UID, canon, buckets: BUCKETS, allowed: [legacy]}).urls) === JSON.stringify([legacy, own(1)]));
check('таҳрир: эски рўйхатда ЙЎҚ бегона URL барибир рад',
    !!checkImageUrls(['https://evil.example/new.jpg'], {uid: UID, canon, buckets: BUCKETS, allowed: [legacy]}).invalid);
check('бўш/нотўғри кириш йиқитмайди',
    JSON.stringify(checkImageUrls(undefined, {uid: UID, canon, buckets: BUCKETS}).urls) === '[]' &&
    JSON.stringify(checkImageUrls([null, 5, ''], {uid: UID, canon, buckets: BUCKETS}).urls) === '[]');

// ── банд ўринлар ──
const NOW = Date.parse('2026-10-18T00:00:00Z');
const ts = (ms) => ({toMillis: () => ms});
check('countActive: блокланган ва муддати ўтган саналмайди',
    countActiveFromDocs([
      {status: 'active', expiresAt: ts(NOW + 1000)},
      {status: 'pending'},
      {status: 'blocked', expiresAt: ts(NOW + 1000)},
      {status: 'active', expiresAt: ts(NOW - 1000)},
    ], NOW) === 2);
check('countActive: data() функцияли ҳужжатлар ва бўш рўйхат',
    countActiveFromDocs([{data: () => ({status: 'active'})}], NOW) === 1 && countActiveFromDocs([], NOW) === 0);
check('storageBucketsFor: лойиҳадан ва созламадан',
    storageBucketsFor('p', 'custom').join(',') === 'custom,p.firebasestorage.app,p.appspot.com' &&
    storageBucketsFor('', '').length === 0);

const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
