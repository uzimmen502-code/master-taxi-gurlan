// КАНОН ШАКЛ ПАРИТЕТИ — Dart ва сервер АЙНАН бир хил натижа бериши.
//
//   flutter test test/features/demand_offer/canon_parity_test.dart
//
// НЕГА БУ ТЕСТ АЛОҲИДА: луғат СЕРВЕРДА канонлаштирилади
// (`functions_demand/core/text.js` → `canonText`), фойдаланувчи инпути
// эса ИЛОВАДА (`IntentRouter._canon`). Иккиси бир хил бўлмаса, луғат
// калити билан сўров ҳеч қачон учрашмайди — ва бу ЖИМГИНА содир
// бўлади: хато чиқмайди, шунчаки «AVA тушунмади».
//
// Ҳақиқий мисол (шу тест топган): «Курьер» да `ь` белгиси бор.
// Сервер уни «kur er» (бўшлиқ билан) қилади, чунки `toLatin` жадвалида
// `ь` йўқ ва у кейин regex билан бўшлиққа айланади. Илова бошқача
// қилса — «Курьер керак» сўрови ишламайди.
//
// Кутилган қийматлар СЕРВЕРДА ҳисобланган (`canonText`), қўлда
// ёзилмаган.

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/demand_offer/intent/intent_router.dart';

void main() {
  // Сервердаги `canonText` натижалари — `node -e` билан олинган.
  const expected = <String, String>{
    'Курьер керак': 'kurer kerak',
    'kuryer kerak': 'kuryer kerak',
    'Тошкентга такси керак': 'toshkentga taksi kerak',
    '500 дона футболка керак': '500 dona futbolka kerak',
    '3 хонали квартира керак': '3 xonali kvartira kerak',
    'Сантехник керак': 'santexnik kerak',
    'Электрик керак': 'elektrik kerak',
    'кран оқяпти': 'kran oqyapti',
    'ток йўқ': "tok yo'q",
    'уй тозалаш керак': 'uy tozalash kerak',
    'қудуқ насос': 'quduq nasos',
    'ғишт терувчи': "g'isht teruvchi",
    'ҳаммом': 'hammom',
    'ўзбек': "o'zbek",
    'котёл ишламайди': 'kotyol ishlamaydi',
  };

  test('канон шакл СЕРВЕР билан айнан бир хил', () {
    final mismatches = <String>[];
    expected.forEach((input, want) {
      final got = IntentRouter.canonForTest(input);
      if (got != want) {
        mismatches.add('«$input»: сервер "$want", илова "$got"');
      }
    });
    expect(
      mismatches,
      isEmpty,
      reason: 'Канон шакл ажралиб кетди — луғат калити билан сўров '
          'учрашмайди:\n${mismatches.join('\n')}',
    );
  });

  test('`ь` ва `ъ` ТЎҒРИ олиб ташланади', () {
    // Бу тест production'даги нозик камчиликни топди:
    // `marketToLatin` да `map[c] || c` ишлатилган, бўш сатр эса JS'да
    // falsy — шунинг учун `ь` ва `ъ` ҳеч қачон олиб ташланмай, ўзгармаган
    // ҳолда ўтиб кетарди («курьер» → «kurьer» → «kur er»).
    //
    // Ядро нусхаси (`functions_demand/core/text.js`) `hasOwnProperty`
    // билан текширади ва тўғри ишлайди. Иккала томон энди бир хил.
    expect(IntentRouter.canonForTest('курьер'), 'kurer');
    expect(IntentRouter.canonForTest('подъезд'), 'podezd');
    expect(IntentRouter.canonForTest('посилка'), 'posilka');
  });

  test('апостроф шакллари бир хил канонга тушади', () {
    const forms = ["o'zbek", 'oʻzbek', 'oʼzbek', 'o’zbek'];
    final out = forms.map(IntentRouter.canonForTest).toSet();
    expect(out.length, 1, reason: 'турли натижа: $out');
  });

  test('тинish белгилари ва кўп бўшлиқ тозаланади', () {
    expect(
      IntentRouter.canonForTest('  Сантехник,   керак!!! '),
      'santexnik kerak',
    );
  });

  test('бўш ва null-га яқин кирилишлар', () {
    expect(IntentRouter.canonForTest(''), '');
    expect(IntentRouter.canonForTest('   '), '');
    expect(IntentRouter.canonForTest('!!!'), '');
  });
}
