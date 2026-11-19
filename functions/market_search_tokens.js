/**
 * «Бозорлар» + кўчмас мулк: сервер қидируви учун `searchTokens` (2026-11-16).
 *
 * НИМА: `tv_shop_items` ва `realty_listings` ҳужжатларига сервер `searchTokens` ёзади — клиент
 *   `where('searchTokens', arrayContains: <сўз>)` билан Firestore'да қидира олсин (юкланган рўйхат ичида эмас).
 * ТРИГГЕРЛАР (янги; мавжуд live функцияларга тегилмайди):
 *   - onShopItemSearchTokens (tv_shop_items onWrite) — title + description дан;
 *   - onRealtySearchTokens  (realty_listings onWrite) — title + text дан (телефон/манзил/ном — ЙЎҚ).
 *   Фақат `searchTokens` ёзилади (updatedAt/status ва б. — йўқ). Тенг бўлса ёзмайди → ўз ёзувидан loop йўқ.
 *   onShopItemModeration'нинг CONTENT_FIELDS рўйхатида `searchTokens` йўқ — бу ёзув «эга таҳрири» эмас.
 *
 * ТОКЕНЛАШ — клиент билан БИР ХИЛ нормализация: `lib/features/ads/utils/ad_search_text.dart`
 *   (`AdSearchText._words / foldMarks / toLatin / toCyrillic`) бу ерга сўзма-сўз кўчирилган
 *   (функциялар `index.js` даги `buildMarketSearchTokens`/`marketToLatin` билан ҳам бир хил, фақат
 *   клиентдаги `foldMarks` қўшилган). Фарқи — сўз бошлари (prefix, ≥3 ҳарф) ҳам қўшилади, лимит 60:
 *     1) title сўзлари: асл + лотин + кирилл;  2) title сўз бошлари (ҳар уч ёзувда);
 *     3) тавсиф сўзлари;                         4) тавсиф сўз бошлари.
 *   Клиентнинг `AdSearchText.queryTokens` (бутун сўз) токенлари шу тўпламнинг ичида — мос келади.
 */
'use strict';

const MAX_TOKENS = 60;
const MIN_TOKEN_LEN = 2; // = AdSearchText.minTokenLen
const PREFIX_MIN_LEN = 3; // PROPOSED: 2 ҳарфли бош жуда кўп мос келади
const PREFIX_MAX_LEN = 15;

// AdSearchText._wordSplit (toLowerCase'дан кейин қўлланади; ң синфда йўқ — клиентда ҳам шундай).
const WORD_SPLIT = /[^0-9a-zA-Zа-яёўқғҳА-ЯЁЎҚҒҲʻʼ']+/u;
const MARKS = /[ʻʼʽˈ`´‘’′]/g;

const TO_LATIN = Object.freeze({
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l',
  м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'x', ц: 'ts', ч: 'ch', ш: 'sh',
  щ: 'sh', ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya', ҳ: 'h', қ: 'q', ғ: "g'", ў: "o'", ң: 'ng',
});
// Тартиб муҳим (Dart const Map тартиби билан бир хил).
const CYR_DIGRAPHS = Object.freeze([
  ['sh', 'ш'], ['ch', 'ч'], ['yo', 'ё'], ['yu', 'ю'], ['ya', 'я'], ['ts', 'ц'], ['ng', 'ң'],
  ["o'", 'ў'], ["g'", 'ғ'], ['ʻ', ''], ['ʼ', ''],
]);
const CYR_SINGLES = Object.freeze({
  q: 'қ', h: 'ҳ', a: 'а', b: 'б', v: 'в', g: 'г', d: 'д', e: 'е', j: 'ж', z: 'з', i: 'и', y: 'й', k: 'к',
  l: 'л', m: 'м', n: 'н', o: 'о', p: 'п', r: 'р', s: 'с', t: 'т', u: 'у', f: 'ф', x: 'х',
});

// Янги лотин алифбоси (эга 2026-11-19): ö ğ ş ç → ЭСКИ шакл (o' g' sh ch) — UzScript.foldLatin билан бир хил.
// Шунда янги ёзувдаги матн ҳам аввалги токенларни беради (сақланган searchTokens ва клиент сўрови мос).
const NEW_TO_OLD = Object.freeze({ ö: "o'", Ö: "O'", ğ: "g'", Ğ: "G'", ş: 'sh', Ş: 'Sh', ç: 'ch', Ç: 'Ch' });
const NEW_LETTERS = /[öÖğĞşŞçÇ]/g;
/** UzScript.foldLatin */
function foldLatin(s) {
  return String(s == null ? '' : s).replace(NEW_LETTERS, (m) => NEW_TO_OLD[m]);
}

/** AdSearchText.foldMarks */
function foldMarks(s) {
  return foldLatin(String(s == null ? '' : s).toLowerCase()).replace(MARKS, "'");
}
/** AdSearchText.toLatin */
function toLatin(s) {
  return foldMarks(s).split('').map((c) => (TO_LATIN[c] === undefined ? c : TO_LATIN[c])).join('');
}
/** AdSearchText.toCyrillic */
function toCyrillic(s) {
  let r = foldMarks(s);
  for (const [k, v] of CYR_DIGRAPHS) r = r.split(k).join(v);
  return r.split('').map((c) => CYR_SINGLES[c] || c).join('');
}
/** AdSearchText._words */
function words(text) {
  return foldLatin(String(text == null ? '' : text).toLowerCase()).split(WORD_SPLIT)
    .map((w) => w.trim()).filter((w) => w.length >= MIN_TOKEN_LEN);
}

function variants(w) {
  return [w, toLatin(w), toCyrillic(w)].filter((v) => v.length >= MIN_TOKEN_LEN);
}

/**
 * Матн қисмларидан (биринчиси — энг муҳими, масалан title) токенлар. Детерминистик, ≤ MAX_TOKENS.
 * @param {string[]} parts
 */
function buildSearchTokens(parts) {
  const out = new Set();
  const add = (t) => { if (out.size < MAX_TOKENS && t.length >= MIN_TOKEN_LEN) out.add(t); };
  for (const part of parts) {
    const ws = words(part);
    for (const w of ws) variants(w).forEach(add);
    for (const w of ws) {
      for (const v of variants(w)) {
        const top = Math.min(v.length - 1, PREFIX_MAX_LEN);
        for (let k = PREFIX_MIN_LEN; k <= top; k += 1) {
          const p = v.slice(0, k);
          if (!p.endsWith("'")) add(p);
        }
      }
    }
    if (out.size >= MAX_TOKENS) break;
  }
  return Array.from(out);
}

const str = (v) => (typeof v === 'string' ? v : '');
/** tv_shop_items: title + description. */
const shopItemTokens = (d) => buildSearchTokens([str((d || {}).title), str((d || {}).description)]);
/** realty_listings: title + text (PII йўқ: ownerName, addressText, телефон — олинмайди). */
const realtyTokens = (d) => buildSearchTokens([str((d || {}).title), str((d || {}).text)]);

const SOURCES = Object.freeze({
  tv_shop_items: { fields: ['title', 'description'], build: shopItemTokens },
  realty_listings: { fields: ['title', 'text'], build: realtyTokens },
});

function sameTokens(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) if (a[i] !== b[i]) return false;
  return true;
}

/**
 * Тоза режа: ёзиш керак бўлса — янги токенлар, бўлмаса null.
 * Ўчирилган ҳужжат — null. Ҳар ёзувда ҳисобланади (тоза, арзон) — манба ўзгарса, токен йўқ ёки
 * бошқа ёзувчи бузган бўлса ҳам тузатилади; тенг бўлса — null (ўз ёзувидан loop йўқ).
 */
function planTokens(collection, before, after) {
  if (!after) return null;
  const next = SOURCES[collection].build(after);
  return sameTokens(after.searchTokens, next) ? null : next;
}

function attachMarketSearchTokens(exportsObj, deps) {
  const { functions, db } = deps;
  const log = (fields) => console.log(JSON.stringify({ module: 'market_search_tokens', ...fields }));

  function trigger(collection, action) {
    return functions.firestore
      .document(`${collection}/{docId}`)
      .onWrite(async (change, context) => {
        if (!change.after.exists) return null;
        const before = change.before.exists ? (change.before.data() || {}) : null;
        if (!planTokens(collection, before, change.after.data() || {})) return null;
        const docId = context.params.docId;
        const started = Date.now();
        // Транзакция: жорий ҳужжатдан ҳисоблаймиз — орада келган таҳрир эскирган токен билан ёпилмасин.
        const result = await db.runTransaction(async (t) => {
          const snap = await t.get(change.after.ref);
          if (!snap.exists) return 'gone';
          const cur = snap.data() || {};
          const next = SOURCES[collection].build(cur);
          if (sameTokens(cur.searchTokens, next)) return 'noop';
          t.update(change.after.ref, { searchTokens: next });
          return 'written';
        });
        log({ action, docId, result, duration: Date.now() - started });
        return null;
      });
  }

  exportsObj.onShopItemSearchTokens = trigger('tv_shop_items', 'onShopItemSearchTokens');
  exportsObj.onRealtySearchTokens = trigger('realty_listings', 'onRealtySearchTokens');
}

module.exports = {
  attachMarketSearchTokens,
  buildSearchTokens,
  shopItemTokens,
  realtyTokens,
  planTokens,
  sameTokens,
  foldMarks,
  toLatin,
  toCyrillic,
  words,
  SOURCES,
  MAX_TOKENS,
  PREFIX_MIN_LEN,
};
