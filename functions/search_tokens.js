'use strict';

/**
 * Қидирув токенлари — ягона манба (2026-10-25: `index.js`дан кўчирилди, алгоритм ЎЗГАРМАДИ). Бир қоида —
 * бир жой (7-банд): бозор эълонлари (`buildMarketSearchTokens`, index.js), глобал қидирув индекси
 * (`buildSearchIndexTokens`) ва онлайн дўкон индекси (`shop_search_index.js`) шу функцияларни ишлатади.
 * Dart томон: `lib/features/ads/utils/ad_search_text.dart` (`AdSearchText.buildTokens`).
 */

const SEARCH_INDEX_MAX_TOKENS = 64;

function marketToLatin(s) {
  const map = {
    а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z',
    и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r',
    с: 's', т: 't', у: 'u', ф: 'f', х: 'x', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sh',
    ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya', ҳ: 'h', қ: 'q', ғ: "g'",
    ў: "o'", ң: 'ng',
  };
  return String(s || '').toLowerCase().split('').map((c) => map[c] || c).join('');
}

function marketToCyrillic(s) {
  let result = String(s || '').toLowerCase();
  const digraphs = {
    sh: 'ш', ch: 'ч', yo: 'ё', yu: 'ю', ya: 'я', ts: 'ц', ng: 'ң',
    "o'": 'ў', "g'": 'ғ',
  };
  for (const [k, v] of Object.entries(digraphs)) {
    result = result.split(k).join(v);
  }
  const singles = {
    q: 'қ', h: 'ҳ', a: 'а', b: 'б', v: 'в', g: 'г', d: 'д', e: 'е', j: 'ж',
    z: 'з', i: 'и', y: 'й', k: 'к', l: 'л', m: 'м', n: 'н', o: 'о', p: 'п',
    r: 'р', s: 'с', t: 'т', u: 'у', f: 'ф', x: 'х',
  };
  return result.split('').map((c) => singles[c] || c).join('');
}

function buildSearchIndexTokens(...parts) {
  const text = parts.filter(Boolean).join(' ').toLowerCase();
  const words = text.split(/[^0-9a-zа-яёўқғҳʻʼ']+/i).filter(
    (w) => w && w.length >= 2,
  );
  const out = new Set();
  for (const w of words) {
    out.add(w);
    const latin = marketToLatin(w);
    const cyrl = marketToCyrillic(w);
    if (latin.length >= 2) out.add(latin);
    if (cyrl.length >= 2) out.add(cyrl);
    if (out.size >= SEARCH_INDEX_MAX_TOKENS) break;
  }
  return Array.from(out).slice(0, SEARCH_INDEX_MAX_TOKENS);
}

module.exports = {
  SEARCH_INDEX_MAX_TOKENS, marketToLatin, marketToCyrillic, buildSearchIndexTokens,
};
