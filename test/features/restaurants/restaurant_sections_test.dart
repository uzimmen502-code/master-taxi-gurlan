// Бўлимлар (S3, D-REST-16/19/20/33): созлама, индекс ҳужжати модели ва ТАРТИБЛАШ. Бўлимга кириш
// қоидаси серверда (`functions/test/restaurant_dish_index_cf.test.js`); бу ерда — клиент томони ва
// сервер билан мослик.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 19, 12);
const _cfg = RestaurantSectionsConfig();

SectionDish _d(
  String id, {
  String rest = 'r1',
  int price = 40000,
  int? pp,
  int sum = 0,
  int count = 0,
  int? listedDaysAgo,
  int prep = 25,
  String? cuisine,
  String? group,
  DateTime? stopUntil,
  DateTime? paused,
  double? lat,
  double? lng,
}) =>
    SectionDish(
      restaurantId: rest,
      itemId: id,
      name: id,
      price: price,
      pricePerPerson: pp,
      restaurantName: 'Rest $rest',
      ratingSum: sum,
      ratingCount: count,
      prepTimeMin: prep,
      cuisineId: cuisine,
      cuisineGroup: group,
      listedAt: listedDaysAgo == null ? null : _now.subtract(Duration(days: listedDaysAgo)),
      stopUntil: stopUntil,
      pausedUntil: paused,
      restaurantLat: lat,
      restaurantLng: lng,
    );

List<String> _ids(List<RankedDish> r) => [for (final x in r) x.dish.itemId];

List<RankedDish> _rank(List<SectionDish> d, RestaurantSection s, {RestaurantSectionsConfig cfg = _cfg, double? lat, double? lng}) =>
    rankSectionDishes(d, section: s, config: cfg, now: _now, lat: lat, lng: lng);

void main() {
  group('Сервер билан мослик', () {
    test('бўлим калитлари сервердаги SECTION билан бир хил тўплам', () {
      final js = File('functions/restaurant_dish_index.js').readAsStringSync();
      final block = RegExp(r'const SECTION = Object\.freeze\(\{([^}]*)\}\)').firstMatch(js)!.group(1)!;
      final server = RegExp(r"(\w+):\s*'(\w+)'").allMatches(block).map((m) => m.group(2)!).toSet();
      expect(RestaurantSection.values.map((s) => s.key).toSet(), server);
    });

    test('созлама бошланғич қийматлари сервердаги DEFAULTS билан бир хил (эга: 5.0 / 5 / 30 / 3)', () {
      final js = File('functions/restaurant_sections_config.js').readAsStringSync();
      final block = RegExp(r'const DEFAULTS = Object\.freeze\(\{([^}]*)\}\)').firstMatch(js)!.group(1)!;
      final m = {for (final x in RegExp(r'(\w+):\s*([\d.]+)').allMatches(block)) x.group(1)!: double.parse(x.group(2)!)};
      expect(m['cheapRatingThreshold'], RestaurantSectionsConfig.defaultCheapRatingThreshold);
      expect(m['newMaxRatings'], RestaurantSectionsConfig.defaultNewMaxRatings);
      expect(m['newMaxDays'], RestaurantSectionsConfig.defaultNewMaxDays);
      expect(m['newPerRestaurantPerSection'], RestaurantSectionsConfig.defaultNewPerRestaurantPerSection);
    });

    test('бўлим номлари 3 тилда мавжуд (restaurants_section_*)', () {
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final s in RestaurantSection.values) {
          expect(m[s.l10nKey], isA<String>(), reason: '$lang ${s.l10nKey}');
          expect((m[s.l10nKey] as String).trim(), isNotEmpty);
        }
        expect(m['restaurants_section_all'], isNotNull, reason: lang);
      }
    });

    test('«Миллий» ва «Дунё» — кухна фильтри бор икки АЛОҲИДА бўлим; қолганларида фильтр йўқ', () {
      expect(RestaurantSection.values.where((s) => s.hasCuisineFilter), [RestaurantSection.national, RestaurantSection.world]);
    });
  });

  group('RestaurantSectionsConfig', () {
    test('ҳужжат йўқ/бузилган — ҳамма бўлим ЎЧИҚ, сон қийматлар эга қийматлари', () {
      for (final c in [RestaurantSectionsConfig.fromMap(null), RestaurantSectionsConfig.fromMap(const {}), RestaurantSectionsConfig.fromMap({'sections': 'x'})]) {
        expect(c.visibleFor('998901234567'), isEmpty);
        expect(c.cheapRatingThreshold, 5.0);
        expect([c.newMaxRatings, c.newMaxDays, c.newPerRestaurantPerSection], [5, 30, 3]);
      }
    });

    test('public — ҳамма; internal — фақат синовчи; off ва нотаниш қиймат — ҳеч ким', () {
      final c = RestaurantSectionsConfig.fromMap({
        'version': 3,
        'sections': {'cheap': 'public', 'national': 'internal', 'world': 'off', 'fast': 'PUBLIC', 'light': 5, 'unknown': 'public'},
        'testerIds': ['998901234567'],
      });
      expect(c.version, 3);
      expect(c.visibleFor(null), [RestaurantSection.cheap]);
      expect(c.visibleFor('998909999999'), [RestaurantSection.cheap]);
      expect(c.visibleFor('998901234567'), [RestaurantSection.cheap, RestaurantSection.national], reason: 'тартиб ўзгармас, синовчига internal ҳам');
      expect(c.isVisible(RestaurantSection.fast, '998901234567'), isFalse, reason: 'катта ҳарфли «PUBLIC» — нотўғри қиймат');
      expect(c.isVisible(RestaurantSection.light, '998901234567'), isFalse);
      expect(c.isVisible(RestaurantSection.national, ''), isFalse);
    });

    test('сон қийматлар чегарадан ташқарида — default; чегарада — қабул', () {
      var c = RestaurantSectionsConfig.fromMap({'cheapRatingThreshold': 0.5, 'newMaxRatings': 0, 'newMaxDays': 400, 'newPerRestaurantPerSection': 2.5});
      expect([c.cheapRatingThreshold, c.newMaxRatings, c.newMaxDays, c.newPerRestaurantPerSection], [5.0, 5, 30, 3]);
      c = RestaurantSectionsConfig.fromMap({'cheapRatingThreshold': 4.25, 'newMaxRatings': 100, 'newMaxDays': 365, 'newPerRestaurantPerSection': 20});
      expect([c.cheapRatingThreshold, c.newMaxRatings, c.newMaxDays, c.newPerRestaurantPerSection], [4.25, 100, 365, 20]);
      c = RestaurantSectionsConfig.fromMap({'cheapRatingThreshold': 1, 'newMaxRatings': 1, 'newMaxDays': 1, 'newPerRestaurantPerSection': 1});
      expect([c.cheapRatingThreshold, c.newMaxRatings, c.newMaxDays, c.newPerRestaurantPerSection], [1.0, 1, 1, 1]);
    });
  });

  group('SectionDish', () {
    test('fromMap: тўлиқ ҳужжат; нотўғри қийматлар «йўқ»; бузилган агрегат — баҳосиз', () {
      final d = SectionDish.fromMap({
        'restaurantId': 'r1', 'itemId': 'osh', 'name': 'Osh', 'price': 40000, 'pricePerPerson': 10000, 'servings': 4,
        'kcal': 600, 'protein': 30, 'fat': 25, 'carbs': 60, 'cuisineGroup': 'national', 'cuisineId': 'national_ozbek',
        'tags': ['kids', 5], 'sections': ['cheap', 'kids'], 'restaurantName': 'Gurlan', 'restaurantLat': 41.84, 'restaurantLng': 60.39,
        'prepTimeMin': 25, 'ratingSum': 47, 'ratingCount': 10,
        'openingHours': {'open': '09:00', 'close': '22:00'},
      });
      expect([d.key, d.pricePerPerson, d.servings, d.hasNutrition, d.cuisineId], ['r1_osh', 10000, 4, true, 'national_ozbek']);
      expect(d.tags, ['kids']);
      expect(d.ratingAvg, closeTo(4.7, 1e-9));
      expect(d.openingHours?.label, '09:00–22:00');

      final bad = SectionDish.fromMap({'restaurantId': 'r', 'itemId': 'i', 'pricePerPerson': 0, 'servings': 99, 'kcal': 9999, 'cuisineGroup': 'x', 'cuisineId': 'y', 'prepTimeMin': 2, 'ratingSum': 999, 'ratingCount': 2});
      expect([bad.pricePerPerson, bad.servings, bad.kcal, bad.cuisineId, bad.prepTimeMin], [null, null, null, null, 20]);
      expect([bad.ratingSum, bad.ratingCount, bad.ratingAvg], [0, 0, 0], reason: 'ўртача 1..5 дан чиқмайди');
      expect(SectionDish.fromMap(const {}).restaurantId, '');
    });

    test('«Янги»: <5 баҳо ва ≤30 кун; чегарада: 4 баҳо — ҳа, 5 — йўқ; 30 кун — ҳа, 31 — йўқ; listedAt йўқ — йўқ', () {
      expect(_d('a', count: 4, sum: 16, listedDaysAgo: 2).isNewAt(_now, _cfg), isTrue);
      expect(_d('a', count: 5, sum: 20, listedDaysAgo: 2).isNewAt(_now, _cfg), isFalse);
      expect(_d('a', listedDaysAgo: 30).isNewAt(_now, _cfg), isTrue);
      expect(_d('a', listedDaysAgo: 31).isNewAt(_now, _cfg), isFalse);
      expect(_d('a').isNewAt(_now, _cfg), isFalse);
      expect(_d('a', listedDaysAgo: -1).isNewAt(_now, _cfg), isTrue, reason: 'соат фарқи (келажак) — ҳали янги');
      final strict = RestaurantSectionsConfig.fromMap({'newMaxRatings': 1, 'newMaxDays': 7});
      expect(_d('a', listedDaysAgo: 8).isNewAt(_now, strict), isFalse);
      expect(_d('a', count: 1, sum: 5, listedDaysAgo: 1).isNewAt(_now, strict), isFalse);
    });

    test('meetsRating (5.0 — қатъий): фақат ўртача 5.0; 4.8, баҳосиз, 4.99 — йўқ; бутун сон ҳисоби (float хатосиз)', () {
      expect(_d('a', sum: 25, count: 5).meetsRating(5.0), isTrue);
      expect(_d('a', sum: 5, count: 1).meetsRating(5.0), isTrue);
      expect(_d('a', sum: 24, count: 5).meetsRating(5.0), isFalse);
      expect(_d('a', sum: 499, count: 100).meetsRating(5.0), isFalse);
      expect(_d('a').meetsRating(5.0), isFalse);
      expect(_d('a', sum: 24, count: 5).meetsRating(4.8), isTrue, reason: '24/5 = 4.8 аниқ, чегарага ТЕНГ');
      expect(_d('a', sum: 14, count: 3).meetsRating(4.66), isTrue, reason: '14/3 = 4.666… ≥ 4.66');
      expect(_d('a', sum: 14, count: 3).meetsRating(4.67), isFalse, reason: '4.666… < 4.67');
    });

    test('очиқлик: пауза; тўхтатилган таом', () {
      expect(_d('a', paused: _now.add(const Duration(minutes: 5))).isRestaurantOpenAt(_now), isFalse);
      expect(_d('a', paused: _now.subtract(const Duration(minutes: 5))).isRestaurantOpenAt(_now), isTrue);
      expect(_d('a', stopUntil: _now.add(const Duration(hours: 1))).isAvailableAt(_now), isFalse);
      expect(_d('a', stopUntil: _now.subtract(const Duration(hours: 1))).isAvailableAt(_now), isTrue);
    });

    test('масофа: координата бор — км; йўқ — null', () {
      final d = _d('a', lat: 41.8586, lng: 60.3917);
      expect(d.distanceKmFrom(41.8406, 60.3917)!, closeTo(2.0, 0.05));
      expect(d.distanceKmFrom(null, null), isNull);
      expect(_d('a').distanceKmFrom(41.8, 60.3), isNull);
    });
  });

  group('Тартиблаш — «Арзон» (D-REST-19/20)', () {
    // Рейтинги чегарада (5.0): B, A. Қолганлар: C (4.8), D (баҳосиз эски).
    final a = _d('A', pp: 9000, sum: 25, count: 5, listedDaysAgo: 90);
    final b = _d('B', pp: 7000, sum: 10, count: 2, listedDaysAgo: 90);
    final c = _d('C', pp: 5000, sum: 24, count: 5, listedDaysAgo: 90);
    final d = _d('D', pp: 4000, listedDaysAgo: 90);

    test('«Янги» тепада; кейин рейтинги чегарадан кам бўлмаганлар нарх ўсиши бўйича; қолганлар пастда шу тартибда; ҳеч ким чиқарилмайди', () {
      final n1 = _d('N1', rest: 'r2', pp: 12000, listedDaysAgo: 1);
      final r = _rank([d, c, a, b, n1], RestaurantSection.cheap);
      expect(_ids(r), ['N1', 'B', 'A', 'D', 'C']);
      expect(r.map((x) => x.isNew), [true, false, false, false, false]);
    });

    test('ресторандан бўлим бошига энг кўпи 3 та «Янги» (энг янгилари); ортиқчаси асосий рўйхатга (поғонада) тушади', () {
      final news = [
        _d('N1', pp: 1000, listedDaysAgo: 5),
        _d('N2', pp: 2000, listedDaysAgo: 4),
        _d('N3', pp: 3000, listedDaysAgo: 3),
        _d('N4', pp: 4500, listedDaysAgo: 20), // энг эски — тепага чиқмайди
      ];
      final r = _rank([...news, a, b, c, d], RestaurantSection.cheap);
      expect(_ids(r).take(3).toList(), ['N1', 'N2', 'N3'], reason: 'блок ичида — бир кишилик нарх ўсиши');
      expect(r.take(3).every((x) => x.isNew), isTrue);
      expect(_ids(r).skip(3).toList(), ['B', 'A', 'D', 'N4', 'C'], reason: 'N4 баҳосиз → пастки поғона, нарх бўйича (4000 < 4500 < 5000)');
      expect(r.firstWhere((x) => x.dish.itemId == 'N4').isNew, isFalse);
    });

    test('икки ресторан: ҳар биридан 3 тагача (чегара ресторан бошига)', () {
      final r1 = [for (var i = 0; i < 4; i++) _d('a$i', rest: 'r1', pp: 1000 + i, listedDaysAgo: i + 1)];
      final r2 = [for (var i = 0; i < 4; i++) _d('b$i', rest: 'r2', pp: 2000 + i, listedDaysAgo: i + 1)];
      final r = _rank([...r1, ...r2], RestaurantSection.cheap);
      expect(r.where((x) => x.isNew).length, 6);
    });

    test('созламадаги чегара ўзгарса (4.8) — C ҳам юқори поғонага чиқади', () {
      final cfg = RestaurantSectionsConfig.fromMap({'cheapRatingThreshold': 4.8});
      expect(_ids(_rank([d, c, a, b], RestaurantSection.cheap, cfg: cfg)), ['C', 'B', 'A', 'D']);
    });

    test('тўхтатилган таом рўйхатга кирмайди; ёпиқ ресторан таомлари ҲАММАСИДАН кейин ва «Янги» эмас', () {
      final stopped = _d('S', pp: 100, stopUntil: _now.add(const Duration(hours: 2)));
      final closedNew = _d('X', rest: 'rc', pp: 500, listedDaysAgo: 1, paused: _now.add(const Duration(hours: 1)));
      final r = _rank([stopped, closedNew, a, d], RestaurantSection.cheap);
      expect(_ids(r), ['A', 'D', 'X']);
      expect([r.last.isClosed, r.last.isNew], [true, false]);
    });

    test('бўш рўйхат; битта таом; тартиб кириш тартибига боғлиқ эмас ва кириш ўзгармайди', () {
      expect(_rank(const [], RestaurantSection.cheap), isEmpty);
      expect(_ids(_rank([a], RestaurantSection.cheap)), ['A']);
      final input = [d, c, a, b];
      final x = _ids(_rank(input, RestaurantSection.cheap));
      final y = _ids(_rank(input.reversed.toList(), RestaurantSection.cheap));
      expect(x, y);
      expect(input.map((e) => e.itemId), ['D', 'C', 'A', 'B'], reason: 'кириш рўйхати ўзгармади');
    });
  });

  group('Тартиблаш — бошқа бўлимлар', () {
    test('«Фаст-фуд»: «Янги» тепада (тайёрлаш вақти бўйича), кейин тайёрлаш вақти, тенгликда рейтинг', () {
      final r = _rank([
        _d('slow', prep: 40, sum: 25, count: 5, listedDaysAgo: 90),
        _d('fastLow', prep: 10, sum: 15, count: 5, listedDaysAgo: 90),
        _d('fastHigh', prep: 10, sum: 25, count: 5, listedDaysAgo: 90),
        _d('newSlow', rest: 'r2', prep: 30, listedDaysAgo: 2),
        _d('newFast', rest: 'r3', prep: 8, listedDaysAgo: 3),
      ], RestaurantSection.fast);
      expect(_ids(r), ['newFast', 'newSlow', 'fastHigh', 'fastLow', 'slow']);
    });

    test('«Миллий» ва бошқалар: «Янги» (энг янгиси олдин), кейин рейтинг (баҳоси борлар олдин; ўртача, сони)', () {
      final r = _rank([
        _d('mid', sum: 22, count: 5, listedDaysAgo: 90), // 4.4
        _d('top', sum: 50, count: 10, listedDaysAgo: 90), // 5.0, 10 та
        _d('topFew', sum: 15, count: 3, listedDaysAgo: 90), // 5.0, 3 та
        _d('none', listedDaysAgo: 90),
        _d('new1', rest: 'r2', listedDaysAgo: 1),
        _d('new2', rest: 'r3', listedDaysAgo: 6),
      ], RestaurantSection.national);
      expect(_ids(r), ['new1', 'new2', 'top', 'topFew', 'mid', 'none']);
    });

    test('рейтинг тенг: яқини олдин, масофасизи охирда', () {
      final near = _d('near', sum: 25, count: 5, listedDaysAgo: 90, lat: 41.85, lng: 60.39);
      final far = _d('far', sum: 25, count: 5, listedDaysAgo: 90, lat: 42.5, lng: 60.39);
      final noGeo = _d('aaa', sum: 25, count: 5, listedDaysAgo: 90);
      expect(_ids(_rank([noGeo, far, near], RestaurantSection.kids, lat: 41.84, lng: 60.39)), ['near', 'far', 'aaa']);
    });

    test('ўртача тенг (5.0): баҳоси кўпроқ олдин', () {
      final r = _rank([
        _d('few', sum: 10, count: 2, listedDaysAgo: 90),
        _d('many', sum: 25, count: 5, listedDaysAgo: 90),
      ], RestaurantSection.light);
      expect(_ids(r), ['many', 'few']);
    });
  });

  group('cuisinesIn — кухна фильтри чиплари', () {
    test('фақат камида битта таоми борлар; сони бўйича камайиш, тенгликда id; кухнасизлар ҳисобга олинмайди', () {
      final out = cuisinesIn([
        _d('1', cuisine: 'national_ozbek', group: 'national'),
        _d('2', cuisine: 'national_ozbek', group: 'national'),
        _d('3', cuisine: 'national_xorazm', group: 'national'),
        _d('4', cuisine: 'national_fargona', group: 'national'),
        _d('5'),
      ]);
      expect(out.map((e) => (e.id, e.count)).toList(), [('national_ozbek', 2), ('national_fargona', 1), ('national_xorazm', 1)]);
      expect(cuisinesIn(const []), isEmpty);
    });
  });
}
