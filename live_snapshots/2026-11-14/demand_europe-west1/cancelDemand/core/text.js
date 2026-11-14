'use strict';

/**
 * MATN NORMALIZATSIYASI VA TRANSLITERATSIYA.
 *
 * `marketToLatin` / `marketToCyrillic` — `functions/index.js:7210` va `:7221`
 * dagi funksiyalarning AYNAN NUSXASI. Nega nusxa: deploy paytida har
 * codebase faqat o'z papkasini yuklaydi.
 *
 * Nega o'zimcha yangisini yozmadim: `search_index` va `searchTokens`
 * allaqachon ayni shu jadval bilan to'ldirilgan. Ikkinchi, boshqacha
 * ishlaydigan transliterator qo'shilsa, yadro bir so'zni, qidiruv
 * boshqasini topadi va buni hech kim sezmaydi.
 *
 * Nusxa `test/text.test.js`dagi paritet testi bilan qulflangan.
 */

/**
 * Kirill -> lotin.
 *
 * Jadval `functions/index.js:7210` (`marketToLatin`) dan olingan, lekin
 * BIR JOYDA ATAYLAB FARQ QILADI — quyidagi izohga qarang.
 */
function toLatin(s) {
  const map = {
    а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z',
    и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r',
    с: 's', т: 't', у: 'u', ф: 'f', х: 'x', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sh',
    ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya', ҳ: 'h', қ: 'q', ғ: "g'",
    ў: "o'", ң: 'ng',
  };

  /**
   * DIQQAT — `map[c] || c` ISHLATILMAYDI.
   *
   * Production'dagi `marketToLatin` aynan shunday yozilgan va unda
   * NOZIK XATO bor: `ъ` va `ь` jadvalda bo'sh satrga (`''`) xaritalangan,
   * bo'sh satr esa JS'da FALSY — shuning uchun `|| c` ishga tushadi va
   * belgi O'CHIRILMAYDI, o'zgarmagan holda o'tib ketadi.
   *
   * Natija: «курьер» -> «kurьer», keyin `canonText` regexi `ь` ni
   * bo'shliqqa aylantiradi -> «kur er» (ikki so'z). Dart tomondagi
   * `AdSearchText.toLatin` esa belgini to'g'ri o'chiradi -> «kurer».
   *
   * Ikki tomon ajralib ketgani uchun «Курьер керак» so'rovi lug'at
   * kaliti bilan HECH QACHON uchrashmasdi — va bu jimgina sodir
   * bo'lardi (xato chiqmaydi, shunchaki «AVA tushunmadi»).
   * Buni `test/features/demand_offer/canon_parity_test.dart` topdi.
   *
   * Shuning uchun yadro nusxasi TO'G'RI ishlaydi: `hasOwnProperty`
   * bilan tekshiriladi va bo'sh satr ham qo'llanadi.
   *
   * Production'dagi `marketToLatin` TUZATILMAYDI: u `search_index` va
   * `searchTokens` ni to'ldirgan, tuzatish butun indeksni qayta
   * qurishni talab qiladi. Yadro bu indeksga tayanmaydi
   * (`active_listings.js` matnni o'zi solishtiradi), shuning uchun farq
   * xavfsiz. Egaga alohida topilma sifatida yetkazilgan.
   */
  return String(s || '')
    .toLowerCase()
    .split('')
    .map((c) => (Object.prototype.hasOwnProperty.call(map, c) ? map[c] : c))
    .join('');
}

/** Lotin -> kirill (loyihaning mavjud jadvali). */
function toCyrillic(s) {
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

/**
 * Apostroflarni birlashtirish.
 *
 * O'zbek lotinida `o'` uchun odamlar beshta xil belgi ishlatadi:
 * ' (ASCII), ʻ (U+02BB), ʼ (U+02BC), ’ (U+2019), ` (grave).
 * Ularni farqlash qidiruvni o'ldiradi.
 */
function unifyApostrophes(s) {
  return String(s || '').replace(/[ʻʼ‘’`´]/g, "'");
}

/**
 * So'z ajratish — loyihaning mavjud regexi bilan bir xil alifbo.
 * Raqamlar saqlanadi («3 xonali», «20 kishiga»).
 */
function tokenize(s) {
  const text = unifyApostrophes(String(s || '')).toLowerCase();
  return text
    .split(/[^0-9a-zа-яёўқғҳʻʼ']+/i)
    .filter((w) => w && w.length >= 2);
}

/**
 * Qidiruv uchun ikkala yozuvdagi shakl.
 *
 * Nega ikkalasi: foydalanuvchi «электрик» deb yozadi, e'lon esa
 * «elektrikman» bo'lishi mumkin (haqiqiy `ads` ma'lumoti).
 */
function variants(word) {
  const w = unifyApostrophes(String(word || '')).toLowerCase();
  const out = new Set();
  if (w.length >= 2) out.add(w);
  const lat = toLatin(w);
  const cyr = toCyrillic(w);
  if (lat.length >= 2) out.add(lat);
  if (cyr.length >= 2) out.add(cyr);
  return Array.from(out);
}

/**
 * Normallashtirilgan, bitta bo'shliqli matn — taqqoslash uchun.
 * Har doim LOTIN shaklga keltiriladi: bitta kanon yozuv bo'lsin.
 *
 * APOSTROF BUTUNLAY TUSHIRIB YUBORILADI.
 *
 * Sabab (o'lchov, 2026-10-03): odamlar telefonda apostrof yozmaydi.
 * Avval kanon shakl apostrofni saqlardi va natijada:
 *   «g'isht teruvchi»  -> topiladi
 *   «gisht teruvchi»   -> TOPILMAYDI   <- real yo'qotish
 * Endi uchalasi ham bitta kanonga tushadi: «ғишт», «g'isht», «gisht».
 *
 * Narxi: `o'` va `o` farqi yo'qoladi (masalan «ўт» va «от» ikkisi ham
 * «ot»). Qisqa so'zlarda nazariy to'qnashuv bor, lekin QIDIRUVDA
 * RECALL aniqlikdan muhimroq: foydalanuvchi kartochkani ko'rib
 * o'zi tasdiqlaydi, noto'g'ri taklif esa shunchaki o'tkazib yuboriladi.
 *
 * Dart tomondagi jufti: `IntentRouter._canon`. Ikkisi
 * `canon_parity_test.dart` bilan qulflangan.
 */
function canonText(s) {
  return toLatin(unifyApostrophes(String(s || '')).toLowerCase())
    .replace(/'/g, '')
    .replace(/[^0-9a-z ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

module.exports = {
  toLatin,
  toCyrillic,
  unifyApostrophes,
  tokenize,
  variants,
  canonText,
};
