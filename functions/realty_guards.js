/**
 * «Кўчмас мулк» — СОФ ҳимоя мантиқи (`functions/realty.js` ишлатади, алоҳида
 * тест қилинади: `functions/test/realty_guards.test.js`).
 *
 *  1) Идемпотентлик калити фойдаланувчига БОҒЛАНАДИ (`idemDocId`): калит
 *     клиентда ясалади, шунинг учун бошқа фойдаланувчининг калити билан
 *     унинг натижасини олиб бўлмасин.
 *  2) Эълон расмлари — фақат ЎЗ Storage'имиздаги `ads/{эга}/…` манзили
 *     (`checkImageUrls`). Аввал сервер фақат `http` билан бошланишини
 *     текширарди: исталган сайтдаги расмни эълонга қўйиш мумкин эди.
 *  3) Банд ўринларни санаш (`countActiveFromDocs`) — транзакция ичида ҳам,
 *     ташқарида ҳам БИР ХИЛ қоида билан.
 */
'use strict';

// Узунлик чегараси паст: калит фойдаланувчига боғланади (`idemDocId`), шунинг
// учун қисқа калит хавфсизликни камайтирмайди; муҳими — ҳужжат ID'сига йўл
// белгилари (`/`, `..`) тушмаслиги. Илова UUID юборади (36 белги).
const IDEM_KEY_RE = /^[A-Za-z0-9_-]{1,64}$/;

function isValidIdemKey(key) {
  return typeof key === 'string' && IDEM_KEY_RE.test(key);
}

/** `wallet_idempotency` ҳужжат ID'си: масъулият соҳаси + фойдаланувчи + калит. */
function idemDocId(scope, uid, key) {
  return `${scope}_${uid}_${key}`;
}

/**
 * Қайтарилган ёзув шу фойдаланувчи ва ШУ ЎЗ сўровники эканини текширади.
 * Бошқа ўлчам/режа билан бир хил калит ишлатилса — хато (жимгина эски
 * натижани қайтариш ўрнига).
 */
function idemMatches(stored, uid, fingerprint) {
  const s = stored || {};
  return s.uid === uid && s.fp === fingerprint;
}

/** Storage'нинг мумкин бўлган bucket номлари (лойиҳа ID'сидан). */
function storageBucketsFor(projectId, configured) {
  const out = new Set();
  if (configured) out.add(String(configured));
  if (projectId) {
    out.add(`${projectId}.firebasestorage.app`);
    out.add(`${projectId}.appspot.com`);
  }
  return [...out];
}

/**
 * [url] `ads/{uid}/…` даги Firebase Storage объектими.
 *
 * [canon] — телефонни каноник кўринишга келтиради (сервердаги
 * `canonicalUid`), шунда `+998…` ва `998…` бир хил ҳисобланади.
 * [buckets] бўш бўлса bucket текширилмайди (созлама йўқ — фақат хост ва йўл).
 */
function isOwnAdsImageUrl(url, uid, canon, buckets) {
  let u;
  try {
    u = new URL(String(url));
  } catch (_) {
    return false;
  }
  if (u.protocol !== 'https:' || u.hostname !== 'firebasestorage.googleapis.com') {
    return false;
  }
  const m = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(u.pathname);
  if (!m) return false;
  if (buckets && buckets.length && !buckets.includes(m[1])) return false;
  let object;
  try {
    object = decodeURIComponent(m[2]);
  } catch (_) {
    return false;
  }
  const parts = object.split('/');
  return parts.length >= 3
    && parts[0] === 'ads'
    && parts[2] !== ''
    && canon(parts[1]) === uid;
}

/**
 * Расм рўйхатини текширади. [allowed] — аллақачон эълонда турган URL'лар
 * (таҳрирда эски расмлар ўз ҳолича қолади: орқага мослик). Қайтаради:
 * `{urls}` (энг кўпи 5) ёки `{invalid: [...]}`.
 */
function checkImageUrls(raw, { uid, canon, buckets, allowed = [], max = 5 }) {
  const list = Array.isArray(raw) ? raw : [];
  const known = new Set(allowed);
  const urls = [];
  const invalid = [];
  for (const u of list) {
    if (typeof u !== 'string' || !u) continue;
    if (known.has(u) || isOwnAdsImageUrl(u, uid, canon, buckets)) {
      if (!urls.includes(u)) urls.push(u);
    } else {
      invalid.push(u);
    }
  }
  if (invalid.length) return { invalid };
  return { urls: urls.slice(0, max) };
}

/** Банд ўринлар сони: блокланган ва муддати ўтганлар саналмайди. */
function countActiveFromDocs(docs, now) {
  let count = 0;
  for (const doc of docs) {
    const d = (doc && typeof doc.data === 'function' ? doc.data() : doc) || {};
    if (d.status === 'blocked') continue;
    const exp = d.expiresAt && d.expiresAt.toMillis ? d.expiresAt.toMillis() : 0;
    if (exp && exp < now) continue;
    count += 1;
  }
  return count;
}

module.exports = {
  isValidIdemKey,
  idemDocId,
  idemMatches,
  storageBucketsFor,
  isOwnAdsImageUrl,
  checkImageUrls,
  countActiveFromDocs,
};
