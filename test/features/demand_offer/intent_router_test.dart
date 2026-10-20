// INTENT ROUTER — СЕРВЕР БИЛАН ПАРИТЕТ.
//
//   flutter test test/features/demand_offer/intent_router_test.dart
//
// НЕГА БУ ТЕСТ ЭНГ МУҲИМЛАРИДАН БИРИ (эга қарори, 2026-10-03):
// «Уста чақириш» алоҳида тугма эмас — АСОСИЙ кириш нуқтаси AVA'дан
// қидириш. Яъни фойдаланувчи «Сантехник керак» деб ёзганда илова буни
// тушуниши шарт. Тушунмаса — бутун пилот ишламайди, чунки бошқа кириш
// нуқтаси йўқ.
//
// Шу билан бирга илова ва сервер БИР ХИЛ тушуниши керак:
//   илова   — матндан категория чиқаради (бу тест)
//   сервер  — эълон матнидан таклифчи категориясини чиқаради
//             (`functions_demand/test/keywords.test.js`)
// Кейслар ЎША ЖОЙДАГИ кейслар билан атайин бир хил.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/ads/utils/ad_search_text.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_enums.dart';
import 'package:ava_gurlan/features/demand_offer/intent/intent_router.dart';

void main() {
  late IntentRouter router;
  late Map<String, dynamic> dict;

  setUpAll(() {
    // Луғат файлини ТЎҒРИДАН-ТЎҒРИ ўқиймиз: `rootBundle` виджет
    // тестида асинхрон ва бу тест соф мантиқни текширади.
    final file = File('assets/data/intent_keywords.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Луғат топилмади. Генерация: '
          'node functions_demand/tools/build_intent_keywords.js',
    );
    dict = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    router = IntentRouter.setForTest(dict);
  });

  group('луғат', () {
    test('40 категория ва етарлича калит', () {
      expect(router.categoryCount, 40);
      // Аниқ сон текширилмайди: луғат қайта генерация қилинганда у
      // ўзгаради (масалан `ь` тузатилгач дубликат калитлар бирлашиб,
      // 402 → 397 бўлди). Чегара фақат «луғат бўш эмас» учун.
      expect(router.keywordCount, greaterThanOrEqualTo(350));
    });

    test('генерация белгиси бор (қўлда таҳрирланмайди)', () {
      expect(dict['_generated'], contains('build_intent_keywords.js'));
      expect(dict['_source'], contains('taxonomy_services.json'));
    });

    test('сервер билан бир хил созламалар', () {
      expect(dict['minPrefixLen'], 4);
      expect(dict['phraseWeight'], 3);
    });
  });

  group('ЭГА АЙТГАН АСОСИЙ КЕЙСЛАР', () {
    // Эга хабарида аниқ ёзилган учта мисол.
    test('«Сантехник керак» → хизмат талаби', () {
      final r = router.detect('Сантехник керак');
      expect(r.module, DemandModule.service);
      expect(r.categoryId, 'santexnik');
      expect(r.showsServiceCard, isTrue);
    });

    test('«Электрик керак» → хизмат талаби', () {
      final r = router.detect('Электрик керак');
      expect(r.module, DemandModule.service);
      expect(r.categoryId, 'elektrik');
    });

    test('«Уста керак» → хизмат талаби деб танилади', () {
      // ДИҚҚАТ: «уста» умумий сўз, аниқ категория бермайди. Лекин
      // карточка КЎРСАТИЛИШИ керак — фойдаланувчи категорияни ўзи
      // танлайди. Акс ҳолда эганинг учинчи мисоли ишламайди.
      final r = router.detect('Уста керак');
      expect(
        r.showsServiceCard,
        isTrue,
        reason: '«Уста керак» хизмат карточкасини кўрсатиши ШАРТ — '
            'эга буни асосий мисол сифатида келтирган',
      );
    });
  });

  group('P0.3 — ЭГА СПЕЦИФИКАЦИЯСИДАГИ БЕШТА МИСОЛ', () {
    // Эга хабари (2026-10-03): қидирув айни шу бешта сўровни тушуниши
    // керак. Улар беш ХИЛ модулга тегишли — Intent Router фақат
    // хизматни эмас, модулни ҳам аниқлайди.

    test('«Курьер керак» → курьер модули', () {
      final r = router.detect('Курьер керак');
      expect(r.module, DemandModule.courier);
      expect(r.showsServiceCard, isTrue);
      // Ядрога ҳали уланмаган — мавжуд экран очилади.
      expect(r.coreReady, isFalse);
      expect(r.existingScreen, 'courier');
      expect(r.opensCoreFlow, isFalse);
    });

    test('«Сантехник керак» → хизмат модули + категория', () {
      final r = router.detect('Сантехник керак');
      expect(r.module, DemandModule.service);
      expect(r.categoryId, 'santexnik');
      // P0 пилоти — ядро оқими очилади.
      expect(r.coreReady, isTrue);
      expect(r.opensCoreFlow, isTrue);
    });

    test('«3 хонали квартира керак» → кўчмас мулк + хона сони', () {
      final r = router.detect('3 хонали квартира керак');
      expect(r.module, DemandModule.realty);
      expect(r.rooms, 3, reason: 'хона сони ажратилиши керак');
      expect(r.existingScreen, 'realty');
    });

    test('«Тошкентга такси керак» → шаҳарлараро такси + манзил', () {
      final r = router.detect('Тошкентга такси керак');
      expect(r.module, DemandModule.intercityTaxi);
      expect(r.destinationHint, 'Тошкент',
          reason: '«Қаерга» майдони олдиндан тўлдирилиши керак');
      expect(r.existingScreen, 'intercity_taxi');
    });

    test('«500 дона футболка керак» → бозор + миқдор (улгуржи)', () {
      final r = router.detect('500 дона футболка керак');
      expect(r.module, DemandModule.market);
      expect(r.quantity, 500, reason: 'миқдор ажратилиши керак');
      // ≥5 — сервер талабни улгуржи деб белгилайди.
      expect(r.quantity! >= 5, isTrue);
    });
  });

  group('P0.3 — ажратиб олиш', () {
    test('лотин шакллари ҳам ишлайди', () {
      expect(router.detect('3 xonali kvartira kerak').rooms, 3);
      expect(router.detect('500 dona futbolka kerak').quantity, 500);
      expect(router.detect('Toshkentga taksi kerak').destinationHint, 'Тошкент');
    });

    test('«кг» бирлиги ҳам миқдор', () {
      expect(router.detect('50 кг картошка керак').quantity, 50);
    });

    test('умумий «-га» қоидаси ИШЛАТИЛМАЙДИ', () {
      // «уйга», «ишга» манзил деб олинмаслиги керак — акс ҳолда
      // «уйга уста керак» сўровида манзил «уй» бўлиб қоларди.
      final r = router.detect('уйга уста керак');
      expect(r.destinationHint, isNull);
      expect(r.showsServiceCard, isTrue, reason: '«уста» умумий калит');
    });

    test('рақамсиз матнда миқдор ҳам, хона ҳам йўқ', () {
      final r = router.detect('квартира керак');
      expect(r.rooms, isNull);
      expect(r.quantity, isNull);
    });

    test('рақам бирликсиз бўлса ажратилмайди', () {
      // «3 керак» — нимадан 3 та? Тахмин қилмаймиз.
      final r = router.detect('3 керак');
      expect(r.quantity, isNull);
      expect(r.rooms, isNull);
    });
  });

  group('P0.3 — модул хизматдан устун', () {
    test('«Тошкентга такси» хизмат категориясига тушмайди', () {
      // «такси» модул калити; агар хизмат биринчи текширилса, нотўғри
      // натижа чиқарди.
      final r = router.detect('Тошкентга такси керак');
      expect(r.module, DemandModule.intercityTaxi);
      expect(r.categoryId, isNull);
    });

    test('«посилка юбориш» → курьер', () {
      expect(router.detect('посилка юбориш').module, DemandModule.courier);
    });

    test('«юк ташиш керак» → юк модули', () {
      expect(router.detect('юк ташиш керак').module, DemandModule.freightLocal);
    });
  });

  group('лотин ва рус варианти', () {
    test('«santexnik kerak» — лотин', () {
      expect(router.detect('santexnik kerak').categoryId, 'santexnik');
    });

    test('«elektrik kerak» — лотин', () {
      expect(router.detect('elektrik kerak').categoryId, 'elektrik');
    });

    test('«сантехник нужен» — рус', () {
      expect(router.detect('сантехник нужен').categoryId, 'santexnik');
    });

    test('«электрик» — ёлғиз сўз', () {
      expect(router.detect('электрик').categoryId, 'elektrik');
    });
  });

  group('СЕРВЕР БИЛАН БИР ХИЛ КЕЙСЛАР', () {
    // `functions_demand/test/keywords.test.js` даги рўйхат.
    const cases = <String, String?>{
      'Курьер керак': null,
      'кран оқяпти': 'santexnik',
      'сув оқяпти': 'santexnik',
      'ток йўқ': 'elektrik',
      'розетка ишламайди': 'elektrik',
      'холодильник не морозит': 'muzlatgich_ustasi',
      'музлатгич совутмаяпти': 'muzlatgich_ustasi',
      'стиральная машина не сливает': 'kir_mashina_ustasi',
      'кондиционер ўрнатиш': 'konditsioner',
      'konditsioner tozalash': 'konditsioner',
      'том оқяпти': 'tom_yopish',
      'эвакуатор керак': 'evakuator',
      'шина монтаж': 'shina_montaj',
      'репетитор математика': 'repetitor',
      'тўй фотограф': 'fotograf',
      '20 кишига ош': 'oshpaz',
      'уй тозалаш керак': 'uy_tozalash',
      'мебель йиғиш': 'mebel_yigish',
      'дарахт кесиш': 'bogbon',
      'ветеринар керак, мол касал': 'veterinar',
      'пластик дераза': 'eshik_deraza',
      'эшик очилмаяпти': 'qulf_ustasi',
      'қудуқ насос': 'quduq_nasos',
    };

    cases.forEach((input, expected) {
      test('«$input» → ${expected ?? '(категория йўқ)'}', () {
        final r = router.detect(input);
        expect(
          r.categoryId,
          expected,
          reason: 'номзодлар: ${r.candidateCategoryIds}',
        );
      });
    });
  });

  group('КЎП МАЪНОЛИ — ЎЗИ ТАНЛАМАЙДИ', () {
    test('«котёл ишламайди» → танлов сўралади', () {
      final r = router.detect('котёл ишламайди');
      expect(r.needsChoice, isTrue, reason: 'номзодлар: ${r.candidateCategoryIds}');
      expect(r.categoryId, isNull, reason: 'AVA ўзи танламаслиги керак');
      final ids = r.candidateCategoryIds.take(2).toList()..sort();
      expect(ids, ['gaz_ustasi', 'isitish_tizimi']);
    });
  });

  group('МОС КЕЛМАСА ЖИМ ТУРАДИ', () {
    // Нотўғри таxмин қилиш — энг ёмон хатти-ҳаракат: сўров 20 та
    // номос одамга кетади ва ҳаммаси push олади.
    const noMatch = [
      'usyaman',
      'нон конвейри ишлашни бошлийди худо халаса',
      'salom qalesiz',
      'Samsung S26',
      'курьер иш',
      'ҳайдовчи бўлиб ишлаш',
      'asdfghjkl',
      '',
      '   ',
      'токайгача борамиз',
    ];

    for (final input in noMatch) {
      test('«$input» → таxмин қилмайди', () {
        final r = router.detect(input);
        expect(
          r.categoryId,
          isNull,
          reason: 'нотўғри таxмин: ${r.categoryId} (${r.candidateCategoryIds})',
        );
      });
    }

    test('аниқ товар номи ҳеч қайси модулга тушмайди', () {
      // «Samsung S26» — аниқ товар. Фойдаланувчи мавжуд эълонларни
      // кўриши керак, карточка эмас.
      expect(router.detect('Samsung S26').showsServiceCard, isFalse);
    });

    test('«3 хонали квартира» ХИЗМАТ эмас, КЎЧМАС МУЛК', () {
      // ДИҚҚАТ: бу тест P0.3 дан кейин ЎЗГАРДИ.
      //
      // Аввал «карточка чиқмаслиги керак» деб текширилган эди, чунки
      // Intent Router фақат хизматни танирди. Эга спецификациясида
      // (2026-10-03) бу сўров АНИҚ келтирилган ва кўчмас мулк талаби
      // деб танилиши керак.
      final r = router.detect('3 хонали квартира');
      expect(r.module, DemandModule.realty);
      expect(r.categoryId, isNull, reason: 'хизмат категорияси эмас');
      expect(r.rooms, 3);
    });

    test('иш қидириш хизмат деб танилмайди', () {
      // Концепция: «курьер иш», «ҳайдовчи бўлиб ишлаш» → хизмат
      // карточкаси ЧИҚМАЙДИ.
      expect(router.detect('курьер иш').showsServiceCard, isFalse);
      expect(router.detect('ҳайдовчи бўлиб ишлаш').showsServiceCard, isFalse);
    });
  });

  group('префикс мослиги', () {
    test('«электрикман» → elektrik (префикс)', () {
      expect(router.detect('электрикман').categoryId, 'elektrik');
    });

    test('қисқа калит префикс бўйича моcлашмайди', () {
      // «ток» (3 белги) «токайгача» га тушиб кетмаслиги керак.
      expect(router.detect('токайгача борамиз').categoryId, isNull);
    });
  });

  group('ибора яккадан устун', () {
    test('«уй тозалаш» кондиционерни ортда қолдиради', () {
      // Бу кейс сервер томонида хато берган эди ва ибора вазни ×3 га
      // оширилиб тузатилган. Dart'да ҳам шундай бўлиши ШАРТ.
      final r = router.detect('уй тозалаш керак');
      expect(r.categoryId, 'uy_tozalash');
      expect(r.needsChoice, isFalse);
    });
  });

  group('транслитерация париteti', () {
    test('AdSearchText.toLatin сервер жадвали билан бир хил', () {
      // Сервер `functions/index.js:7210` (`marketToLatin`) ва
      // `functions_demand/core/text.js` айни шу жадвални ишлатади.
      expect(AdSearchText.toLatin('электрик'), 'elektrik');
      expect(AdSearchText.toLatin('ўзбек'), "o'zbek");
      expect(AdSearchText.toLatin('қудуқ'), 'quduq');
      expect(AdSearchText.toLatin('ҳаммом'), 'hammom');
      expect(AdSearchText.toLatin('ғишт'), "g'isht");
    });

    test('апостроф шакллари бирлаштирилади', () {
      // Фойдаланувчи 5 хил белги ёзиши мумкин.
      final forms = ["ko'chish", 'koʻchish', 'koʼchish', 'ko’chish'];
      final results = forms.map((f) => router.detect('$f kerak').categoryId).toSet();
      expect(results.length, 1,
          reason: 'апостроф шакллари бир хил натижа бериши керак: $results');
    });
  });

  group('барқарорлик', () {
    test('бир хил кирилиш → бир хил натижа', () {
      final a = router.detect('кран оқяпти');
      final b = router.detect('кран оқяпти');
      expect(a.categoryId, b.categoryId);
      expect(a.candidateCategoryIds, b.candidateCategoryIds);
    });

    test('катта-кичик ҳарф аҳамиятсиз', () {
      expect(router.detect('САНТЕХНИК КЕРАК').categoryId, 'santexnik');
      expect(router.detect('сантехник керак').categoryId, 'santexnik');
    });

    test('бўш луғат йиқитмайди', () {
      final empty = IntentRouter.setForTest(<String, dynamic>{});
      expect(empty.isEmpty, isTrue);
      expect(empty.detect('сантехник керак').showsServiceCard, isFalse);
      // Асл луғатни қайтарамиз.
      IntentRouter.setForTest(dict);
    });
  });

  group('категория номлари', () {
    test('учта тилда', () {
      final r = IntentRouter.setForTest(dict);
      expect(r.categoryName('santexnik', 'uz_Cyrl'), 'Сантехник');
      expect(r.categoryName('santexnik', 'uz_Latn'), 'Santexnik');
      expect(r.categoryName('santexnik', 'ru'), 'Сантехник');
    });

    test('номаълум категория — id нинг ўзи (йиқилмайди)', () {
      final r = IntentRouter.setForTest(dict);
      expect(r.categoryName('xayoliy', 'uz_Cyrl'), 'xayoliy');
    });

    test('гуруҳ қайтарилади', () {
      final r = IntentRouter.setForTest(dict);
      expect(r.categoryGroup('santexnik'), 'uy_tamir');
    });

    test('categoryNames — барча 40 категория ID → ном (таклифчи экрани чиплари)', () {
      final r = IntentRouter.setForTest(dict);
      final names = r.categoryNames('uz_Latn');
      expect(names.length, 40);
      expect(names['santexnik'], 'Santexnik');
      expect(names['elektrik'], isNotEmpty);
    });

    test('categoryNames — тил бўйича, ном бўш бўлмайди', () {
      final r = IntentRouter.setForTest(dict);
      expect(r.categoryNames('uz_Cyrl')['santexnik'], 'Сантехник');
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        for (final e in r.categoryNames(lang).entries) {
          expect(e.value.trim(), isNotEmpty, reason: '$lang/${e.key}');
        }
      }
    });

    test('categoryNames — луғат бўш бўлса бўш харита (йиқилмайди)', () {
      final empty = IntentRouter.setForTest(<String, dynamic>{});
      expect(empty.categoryNames('ru'), isEmpty);
      IntentRouter.setForTest(dict);
    });
  });
}
