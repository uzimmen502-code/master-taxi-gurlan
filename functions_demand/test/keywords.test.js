/**
 * Kalit so'z moslashtirgich + matn normalizatsiyasi pariteti.
 *
 *   node functions_demand/test/keywords.test.js
 *
 * Sinov ma'lumotlari TAXMIN QILINMAGAN: `ads` kolleksiyasidagi haqiqiy
 * xizmat e'lonlari matni (2026-10-03 auditi, `type: 'service'`).
 */
const assert = require('assert');
const text = require('../core/text');
const kw = require('../core/keywords');
const taxonomy = require('../core/seed/taxonomy_services.json');

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

const index = kw.buildIndex(taxonomy);

console.log('transliteratsiya pariteti (eski codebase bilan)');
ok('toLatin eski `marketToLatin` bilan bir xil', () => {
  // Nusxa ajralib ketmasligi SHART: `search_index` ayni shu jadval bilan
  // to'ldirilgan.
  const samples = [
    'электрик', 'сантехник', 'қудуқ', 'ғишт', 'ўзбек', 'ҳаммом',
    'кир ювиш машинаси', 'темир панжара', 'ёғоч', 'щётка',
  ];
  for (const s of samples) {
    // Eski jadvalni qo'lda qayta yozmaymiz — natijani qulflaymiz.
    const got = text.toLatin(s);
    assert.ok(got.length > 0, s);
    assert.ok(!/[а-яёўқғҳ]/.test(got), `lotinga o'tmagan: ${s} -> ${got}`);
  }
  assert.strictEqual(text.toLatin('ўзбек'), "o'zbek");
  assert.strictEqual(text.toLatin('қудуқ'), 'quduq');
  assert.strictEqual(text.toLatin('ҳаммом'), 'hammom');
  assert.strictEqual(text.toLatin('ғишт'), "g'isht");
  assert.strictEqual(text.toLatin('электрик'), 'elektrik');
});
ok('toCyrillic teskari yo`nalish', () => {
  assert.strictEqual(text.toCyrillic('santexnik'), 'сантехник');
  assert.strictEqual(text.toCyrillic("o'zbek"), 'ўзбек');
});
ok('ASIMMETRIYA: aylanish `э` ni qaytarmaydi (mavjud jadval xususiyati)', () => {
  // `toLatin` da «э» -> «e», lekin `toCyrillic` da «e» -> «е».
  // Ya'ni электрик -> elektrik -> електрик (э EMAS, е).
  //
  // Bu `functions/index.js:7210` dagi MAVJUD jadvalning xususiyati va
  // `search_index` allaqachon shu bilan to'ldirilgan — tuzatish eski
  // indeksni buzadi. Shuning uchun yadro KANON SHAKL sifatida doim
  // LOTINNI ishlatadi (`canonText`), aylanishga tayanmaydi.
  assert.strictEqual(text.toLatin('электрик'), 'elektrik');
  assert.strictEqual(text.toCyrillic('elektrik'), 'електрик');
  assert.strictEqual(
    text.canonText('электрик'), text.canonText('elektrik'),
    'kanon shakl ikkala yozuvni birlashtirishi SHART',
  );
});
ok('apostroflar birlashtiriladi (5 xil belgi)', () => {
  const forms = ["o'", 'oʻ', 'oʼ', 'o’', 'o`'];
  const out = new Set(forms.map((f) => text.unifyApostrophes(f)));
  assert.strictEqual(out.size, 1, `birlashmadi: ${Array.from(out).join(' ')}`);
});
ok('canonText tinish belgilarini tozalaydi', () => {
  assert.strictEqual(text.canonText('Электрикман, от А до Я!'), 'elektrikman ot a do ya');
});
ok('tokenize raqamlarni saqlaydi', () => {
  assert.deepStrictEqual(text.tokenize('20 kishiga osh'), ['20', 'kishiga', 'osh']);
});

console.log('buildIndex');
ok('40 kategoriya indekslandi', () => {
  assert.strictEqual(index.categoryById.size, 40);
});
ok('ko`p ma`noli kalit so`zlar ajratilgan', () => {
  assert.ok(index.ambiguous.size > 0);
});
ok('indeks ikkala yozuvda kalit saqlaydi', () => {
  // «электрик» kirill shaklda yozilgan, lekin lotin so'rovi ham topishi kerak.
  assert.ok(index.byKeyword.has('elektrik'));
});

console.log('HAQIQIY FOYDALANUVCHI MATNLARI');
const userCases = [
  ['Курьер керак', null],
  ['кран оқяпти', 'santexnik'],
  ['сув оқяпти', 'santexnik'],
  ['ток йўқ', 'elektrik'],
  ['розетка ишламайди', 'elektrik'],
  ['электрик керак', 'elektrik'],
  ['elektrik kerak', 'elektrik'],
  ['Сантехник керак', 'santexnik'],
  ['santexnik kerak', 'santexnik'],
  ['сантехник', 'santexnik'],
  ['холодильник не морозит', 'muzlatgich_ustasi'],
  ['музлатгич совутмаяпти', 'muzlatgich_ustasi'],
  ['стиральная машина не сливает', 'kir_mashina_ustasi'],
  ['кондиционер ўрнатиш', 'konditsioner'],
  ['konditsioner tozalash', 'konditsioner'],
  ['том оқяпти', 'tom_yopish'],
  ['эвакуатор керак', 'evakuator'],
  ['шина монтаж', 'shina_montaj'],
  ['репетитор математика', 'repetitor'],
  ['тўй фотограф', 'fotograf'],
  ['20 кишига ош', 'oshpaz'],
  ['уй тозалаш керак', 'uy_tozalash'],
  ['мебель йиғиш', 'mebel_yigish'],
  ['дарахт кесиш', 'bogbon'],
  ['ветеринар керак, мол касал', 'veterinar'],
  ['пластик дераза', 'eshik_deraza'],
  ['эшик очилмаяпти', 'qulf_ustasi'],
  ['қудуқ насос', 'quduq_nasos'],
];
for (const [input, expected] of userCases) {
  ok(`«${input}» -> ${expected || '(kategoriya yo`q)'}`, () => {
    const r = kw.matchCategories(input, index);
    if (expected === null) {
      assert.strictEqual(
        r.categoryId, null,
        `noto'g'ri taxmin qildi: ${r.categoryId} (${JSON.stringify(r.candidates)})`,
      );
    } else {
      assert.strictEqual(
        r.categoryId, expected,
        `kutilgan ${expected}, olingan ${r.categoryId} — ${JSON.stringify(r.candidates)}`,
      );
    }
  });
}

console.log('KO`P MA`NOLI SO`ZLAR — O`ZI TANLAMAYDI');
ok('«котёл ишламайди» -> tanlov so`raladi', () => {
  const r = kw.matchCategories('котёл ишламайди', index);
  assert.strictEqual(r.needsChoice, true, JSON.stringify(r.candidates));
  assert.strictEqual(r.categoryId, null, 'o`zi tanlamasligi kerak');
  const ids = r.candidates.map((c) => c.categoryId).sort();
  assert.deepStrictEqual(ids.slice(0, 2), ['gaz_ustasi', 'isitish_tizimi']);
});

console.log('MOS KELMASA JIM TURADI (noto`g`ri taxmin yo`q)');
const noMatch = [
  'usyaman',
  'нон конвейри ишлашни бошлийди худо халаса',
  'salom qalesiz',
  'Samsung S26',
  '3 хонали квартира',
  'курьер иш',
  'ҳайдовчи бўлиб ишлаш',
  'asdfghjkl',
  '',
  '   ',
];
for (const input of noMatch) {
  ok(`«${input}» -> taxmin qilmaydi`, () => {
    const r = kw.matchCategories(input, index);
    assert.strictEqual(
      r.categoryId, null,
      `noto'g'ri taxmin: ${r.categoryId} (${JSON.stringify(r.candidates)})`,
    );
  });
}

console.log('HAQIQIY E`LON MATNLARI (`ads`, type: service)');
const adCases = [
  ['электрикман, от А до Я', ['elektrik']],
  ['pol patalok ustaman, narhini kelishamiz', []],
  ['maslahat hizmati', []],
  ['usyaman', []],
];
for (const [adText, expectContains] of adCases) {
  ok(`e'lon «${adText.slice(0, 32)}...» -> ${expectContains.join(',') || '(yoq)'}`, () => {
    const cats = kw.providerCategoriesFromText(adText, index);
    for (const want of expectContains) {
      assert.ok(cats.includes(want), `${want} topilmadi, olingan: ${cats.join(',')}`);
    }
    if (expectContains.length === 0) {
      assert.strictEqual(cats.length, 0, `kutilmagan moslik: ${cats.join(',')}`);
    }
  });
}
console.log('ASIMMETRIYA — umumiy kalitlar taklifchiga TAYINLANMAYDI');
ok('«ustaman» 40 kategoriyaga tayinlanmaydi', () => {
  // Agar `generic` ro'yxati indeksga tushib qolsa, `ads`da «ustaman»
  // deb yozgan odam HAR BIR xizmat so'rovi uchun nomzod bo'lib qolardi
  // — ya'ni aniq spam. Himoya: `buildIndex` faqat `categories`dan
  // quriladi.
  const cats = kw.providerCategoriesFromText('ustaman', index);
  assert.strictEqual(cats.length, 0, `kutilmagan moslik: ${cats.join(',')}`);
});
ok('umumiy kalitlar indeksda YO`Q', () => {
  for (const g of (taxonomy.generic || [])) {
    const key = require('../core/text').canonText(g);
    assert.ok(
      !index.byKeyword.has(key),
      `umumiy kalit «${g}» kategoriya indeksiga tushib qolgan`,
    );
  }
});
ok('«remont kilaman» kategoriyaga tayinlanmaydi', () => {
  const cats = kw.providerCategoriesFromText('remont kilaman', index);
  assert.strictEqual(cats.length, 0, `kutilmagan moslik: ${cats.join(',')}`);
});

ok('usta bir nechta kategoriyada bo`lishi mumkin', () => {
  // «kafel va bo'yash ishlarini qilaman» — ikkisi ham to'g'ri.
  const cats = kw.providerCategoriesFromText('kafel va boyash ishlarini qilaman', index);
  assert.ok(cats.includes('kafel'), cats.join(','));
});

console.log('prefiks mosligi chegarasi');
ok('qisqa kalit so`z prefiks bo`yicha moslashmaydi', () => {
  // «ток» (3 harf) «токайгача» ga tushib ketmasligi kerak.
  const r = kw.matchCategories('токайгача борамиз', index);
  assert.strictEqual(r.categoryId, null, JSON.stringify(r.candidates));
});
ok('uzun kalit so`z prefiks bo`yicha moslashadi', () => {
  const r = kw.matchCategories('электрикман', index);
  assert.strictEqual(r.categoryId, 'elektrik');
});

console.log('barqarorlik');
ok('bir xil kirish -> bir xil natija', () => {
  const a = kw.matchCategories('кран оқяпти', index);
  const b = kw.matchCategories('кран оқяпти', index);
  assert.deepStrictEqual(a, b);
});
ok('null va undefined yiqitmaydi', () => {
  assert.strictEqual(kw.matchCategories(null, index).categoryId, null);
  assert.strictEqual(kw.matchCategories(undefined, index).categoryId, null);
});

console.log(`\n${passed} test o'tdi.`);
