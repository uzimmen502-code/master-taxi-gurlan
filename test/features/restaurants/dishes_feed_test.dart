// «Овқатлар» лентаси (D-REST-40, эга 2026-10-19): «Барчаси» экрани очилганда яқин атрофдаги ТАОМЛАР чиқади — ресторанлар
// рўйхати эмас («одам оч бўлгани учун киради»). Лента — `all` бўлими (feature flag шу бўлим босқичи); ресторанлар —
// алоҳида чип. Яқинлик бўйича тартиб, ёпиқ ресторан охирида, қидирув ресторанга қайтаради.

import 'dart:async';

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

const _lat = 41.8406;
const _lng = 60.3917;
final _now = DateTime(2026, 10, 19, 12);

SectionDish _d(String id, {double? lat, int sum = 0, int count = 0, String rest = 'r1', DateTime? paused, int? listedDaysAgo = 90}) => SectionDish(
      restaurantId: rest,
      itemId: id,
      name: 'Taom $id',
      price: 40000,
      restaurantName: 'Rest $rest',
      ratingSum: sum,
      ratingCount: count,
      restaurantLat: lat,
      restaurantLng: _lng,
      pausedUntil: paused,
      listedAt: listedDaysAgo == null ? null : _now.subtract(Duration(days: listedDaysAgo)),
    );

class _Repo implements RestaurantsRepository {
  _Repo({this.sections = RestaurantSectionsConfig.off, this.dishes = const []});

  final RestaurantSectionsConfig sections;
  final List<SectionDish> dishes;
  final fetched = <RestaurantSection>[];

  @override
  Future<RestaurantSectionsConfig> getSectionsConfig({bool force = false}) async => sections;

  @override
  Future<SectionDishesResult> fetchSectionDishes(RestaurantSection section, {required double lat, required double lng, int limit = 200}) async {
    fetched.add(section);
    return SectionDishesResult([for (final d in dishes) d]);
  }

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];

  @override
  Stream<List<Restaurant>> watchNearby({required double lat, required double lng, double radiusKm = 20, int perCellLimit = 50}) =>
      Stream.value(const [Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved', lat: 41.85, lng: 60.39)]);

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) =>
      Stream.value(const [Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved', lat: 41.85, lng: 60.39)]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Созлама ҲАЛИ келмаган ҳолатни кўрсатиш учун: `config` қўлда тугатилади; ресторанлар оқими очилганини санайди.
class _SlowRepo extends _Repo {
  _SlowRepo({super.sections, super.dishes});

  final config = Completer<RestaurantSectionsConfig>();
  int listStreams = 0;

  @override
  Future<RestaurantSectionsConfig> getSectionsConfig({bool force = false}) => config.future;

  @override
  Stream<List<Restaurant>> watchNearby({required double lat, required double lng, double radiusKm = 20, int perCellLimit = 50}) {
    listStreams++;
    return super.watchNearby(lat: lat, lng: lng, radiusKm: radiusKm, perCellLimit: perCellLimit);
  }

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) {
    listStreams++;
    return super.watchApproved(limit: limit);
  }
}
void main() {
  // «Охирги маълум созлама» (экран очилишини тезлатади) тестлар орасида эскирмасин.
  setUp(RestaurantsListScreen.resetLastKnownConfig);
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('rankSectionDishes(all): яқини олдин', () {
    const cfg = RestaurantSectionsConfig();
    List<String> order(List<SectionDish> d) =>
        rankSectionDishes(d, section: RestaurantSection.all, config: cfg, now: _now, lat: _lat, lng: _lng).map((r) => r.dish.itemId).toList();

    test('рейтинги баландроқ, лекин узоқроқ таом яқин таомдан кейин; масофа тенг бўлса рейтинг', () {
      expect(order([_d('far', lat: 41.95, sum: 50, count: 10), _d('near', lat: 41.8426), _d('mid', lat: 41.88, sum: 20, count: 5)]), ['near', 'mid', 'far']);
      expect(order([_d('b', lat: 41.86, sum: 40, count: 10), _d('a', lat: 41.86, sum: 49, count: 10)]), ['a', 'b']);
    });

    test('координатаси номаълум — охирида; ёпиқ ресторан таоми ҳаммасидан кейин; тўхтатилган таом кирмайди', () {
      final closed = _d('closed', lat: 41.8426, paused: _now.add(const Duration(hours: 5)));
      final noLoc = _d('noloc');
      expect(order([noLoc, closed, _d('open', lat: 41.9)]), ['open', 'noloc', 'closed']);
    });

    test('«Янги» таомлар (баҳоси кам, 30 кундан ошмаган) тепада, ресторан бошига ≤ 3', () {
      final fresh = [for (var i = 0; i < 5; i++) _d('n$i', lat: 41.99, listedDaysAgo: 2 + i)];
      final r = rankSectionDishes([...fresh, _d('old', lat: 41.8426, sum: 45, count: 9)], section: RestaurantSection.all, config: cfg, now: _now, lat: _lat, lng: _lng);
      expect(r.take(3).every((x) => x.isNew), isTrue);
      expect(r.where((x) => x.isNew).length, 3, reason: 'бир ресторандан 3 тагача');
    });
  });

  group('RestaurantSection.all', () {
    test('матн калити — «Овқатлар» (ресторанлар чипи «restaurants_section_all» билан аралашмайди)', () {
      expect(RestaurantSection.all.l10nKey, 'restaurants_section_dishes');
      expect(RestaurantSection.cheap.l10nKey, 'restaurants_section_cheap');
      expect(RestaurantSection.home.l10nKey, 'restaurants_section_home');
      expect(RestaurantSection.home.key, 'home', reason: 'сервердаги SECTION.home билан бир хил');
      expect(tr('restaurants_section_dishes'), isNot(tr('restaurants_section_all')));
    });
  });

  group('«Барчаси» экрани: овқатлар лентаси билан очилади', () {
    const feedOn = RestaurantSectionsConfig(stages: {'all': 'public'});

    Future<void> pump(WidgetTester t, _Repo repo, {double width = 2400}) async {
      t.view.physicalSize = Size(width * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantsListScreen(key: UniqueKey(), repository: repo, currentUid: '998912000001', userLat: _lat, userLng: _lng, locate: () async => null),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('лента ёқилган: экран очилганда ТАОМЛАР (ресторан эмас); «Овқатлар» чипи танланган ва биринчи', (t) async {
      final repo = _Repo(sections: feedOn, dishes: [_d('osh', lat: 41.85)]);
      await pump(t, repo);
      expect(repo.fetched, [RestaurantSection.all]);
      expect(find.byKey(const ValueKey('section-list-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-r1_osh')), findsOneWidget);
      expect(find.text('Gurlan osh'), findsNothing, reason: 'ресторан рўйхати эмас');
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('section-feed'))).selected, isTrue);
      expect(t.getTopLeft(find.byKey(const ValueKey('section-feed'))).dx, lessThan(t.getTopLeft(find.byKey(const ValueKey('section-all'))).dx), reason: '«Овқатлар» биринчи');
      expect(find.byKey(const ValueKey('section-all')), findsOneWidget, reason: 'ресторанлар — алоҳида чип');
    });

    testWidgets('чиплар тартиби (эга, 2026-10-19): Барчаси · Арзон ва тўйимли · Офис буюртма · Фаст-фуд · Миллий таомлар · Дунё таомлари · Ресторанлар · Нонушта · Тунги · Дастурхон буюртма · Парҳезли таомлар; «Болалар» йўқ', (t) async {
      const all = RestaurantSectionsConfig(stages: {
        'all': 'public', 'home': 'public', 'cheap': 'public', 'office': 'public', 'fast': 'public', 'national': 'public', 'world': 'public',
        'breakfast': 'public', 'night': 'public', 'dastarxon': 'public', 'light': 'public', 'kids': 'public', 'seasonal': 'public',
      });
      await pump(t, _Repo(sections: all, dishes: [_d('osh', lat: 41.85)]));
      const keys = ['section-feed', 'section-home', 'section-office', 'section-fast', 'section-national', 'section-world', 'section-all', 'section-breakfast', 'section-night', 'section-dastarxon', 'section-light'];
      final xs = [for (final k in keys) t.getTopLeft(find.byKey(ValueKey(k))).dx];
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]), reason: '${keys[i]} ${keys[i - 1]} дан кейин');
      }
      expect(find.byKey(const ValueKey('section-kids')), findsNothing, reason: '«Болалар» чипи олиб ташланган');
      expect(find.byKey(const ValueKey('section-cheap')), findsNothing, reason: '«Арзон» чипи «Уй таомлари» га алмашган (эга, 2026-10-19)');
      expect(find.text(tr('restaurants_section_home')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-seasonal')), findsNothing, reason: 'ҳозир очиқ мавсум йўқ');
      expect(find.text(tr('restaurants_section_dishes')), findsOneWidget);
    });

    testWidgets('лента ёқилмаган бўлса «Ресторанлар» чипи БИРИНЧИ (экран аввалгидек)', (t) async {
      await pump(t, _Repo(sections: const RestaurantSectionsConfig(stages: {'home': 'public', 'fast': 'public'})));
      expect(t.getTopLeft(find.byKey(const ValueKey('section-all'))).dx, lessThan(t.getTopLeft(find.byKey(const ValueKey('section-home'))).dx));
      expect(find.byKey(const ValueKey('section-feed')), findsNothing);
    });
    testWidgets('«Ресторанлар» чипи рўйхатга ўтказади; «Овқатлар» қайтаради; фойдаланувчи танлови сақланади', (t) async {
      final repo = _Repo(sections: feedOn, dishes: [_d('osh', lat: 41.85)]);
      await pump(t, repo);
      await t.tap(find.byKey(const ValueKey('section-all')));
      await t.pumpAndSettle();
      expect(find.text('Gurlan osh'), findsWidgets);
      expect(find.byKey(const ValueKey('section-list-all')), findsNothing);
      await t.tap(find.byKey(const ValueKey('section-feed')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_osh')), findsOneWidget);
    });

    testWidgets('қидирув ёзилса — ресторанлар рўйхатига қайтади (ном бўйича қидирув)', (t) async {
      final repo = _Repo(sections: feedOn, dishes: [_d('osh', lat: 41.85)]);
      await pump(t, repo);
      await t.enterText(find.byType(TextField).first, 'Gurlan');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-list-all')), findsNothing);
      expect(find.text('Gurlan osh'), findsWidgets);
    });

    testWidgets('лента ЎЧИҚ (созлама йўқ ёки all ёқилмаган): экран аввалгидек — ресторанлар рўйхати, «Овқатлар» чипи йўқ', (t) async {
      for (final cfg in [RestaurantSectionsConfig.off, const RestaurantSectionsConfig(stages: {'cheap': 'public'})]) {
        final repo = _Repo(sections: cfg, dishes: [_d('osh', lat: 41.85)]);
        await pump(t, repo);
        expect(repo.fetched, isEmpty);
        expect(find.byKey(const ValueKey('section-feed')), findsNothing);
        expect(find.text('Gurlan osh'), findsWidgets);
      }
    });

    testWidgets('лента бўш: тушунарли хабар ва «Бутун Ўзбекистон» тугмаси — босилса ресторанлар рўйхати (бутун республика)', (t) async {
      await pump(t, _Repo(sections: feedOn));
      expect(find.text(tr('restaurants_dish_empty')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dishes_show_nation')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-list-all')), findsNothing);
      expect(find.text('Gurlan osh'), findsWidgets);
    });

    testWidgets('2 УСТУН: 360 dp телефонда (ва шрифт ×1.3) икки карточка бир қаторда; 280 dp жуда тор экранда — битта устун', (t) async {
      Future<void> at(double w, double scale) async {
        t.view.physicalSize = Size(w * 3, 1800 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(l10nApp(
          textScale: scale,
          home: RestaurantsListScreen(
            key: UniqueKey(),
            repository: _Repo(sections: feedOn, dishes: [_d('a', lat: 41.85), _d('b', lat: 41.86)]),
            currentUid: '998912000001',
            userLat: _lat,
            userLng: _lng,
            locate: () async => null,
          ),
        ));
        await t.pumpAndSettle();
      }

      await at(360, 1.3);
      final a = t.getTopLeft(find.byKey(const ValueKey('dish-r1_a')));
      final b = t.getTopLeft(find.byKey(const ValueKey('dish-r1_b')));
      expect(a.dy, b.dy, reason: 'бир қаторда');
      expect(b.dx, greaterThan(a.dx));
      expect(t.takeException(), isNull);
      await at(280, 1.0);
      expect(t.getTopLeft(find.byKey(const ValueKey('dish-r1_b'))).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey('dish-r1_a'))).dy), reason: 'тор экранда — устма-уст');
    });
    testWidgets('тор экран 320 + шрифт ×2: лента overflow қилмайди', (t) async {
      t.view.physicalSize = const Size(320 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        textScale: 2.0,
        home: RestaurantsListScreen(
          key: UniqueKey(),
          repository: _Repo(sections: feedOn, dishes: [_d('osh', lat: 41.85, sum: 47, count: 10)]),
          currentUid: '998912000001',
          userLat: _lat,
          userLng: _lng,
          locate: () async => null,
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('«Барчаси» бир қадамда очилади (эга, 2026-10-19: «Кафе-Ресторан» икки қадамда очилаяпти)', () {
    const feedOn = RestaurantSectionsConfig(stages: {'all': 'public'});

    Future<void> open(WidgetTester t, _SlowRepo repo) async {
      t.view.physicalSize = const Size(2400 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantsListScreen(key: UniqueKey(), repository: repo, currentUid: '998912000001', userLat: _lat, userLng: _lng, locate: () async => null),
      ));
    }

    testWidgets('1-очилиш: созлама келгунча ресторанлар рўйхати ЧИЗИЛМАЙДИ (фақат юкланиш), келгач — бевосита таомлар', (t) async {
      final repo = _SlowRepo(sections: feedOn, dishes: [_d('osh', lat: 41.85)]);
      await open(t, repo);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(tr('restaurants_sort_distance')), findsNothing, reason: 'саралаш чиплари (рўйхат режими) чизилмайди');
      expect(find.text('Gurlan osh'), findsNothing);
      expect(repo.listStreams, 0, reason: 'ресторанлар оқими умуман очилмади');

      repo.config.complete(feedOn);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_osh')), findsOneWidget);
      expect(repo.listStreams, 0, reason: 'рўйхат бир лаҳзага ҳам чизилмади — иккинчи қадам йўқ');
      expect(repo.fetched, [RestaurantSection.all]);
    });

    testWidgets('2-очилиш (охирги маълум созлама бор): биринчи кадрдаёқ таомлар лентаси — созламани кутмайди', (t) async {
      final first = _SlowRepo(sections: feedOn, dishes: [_d('osh', lat: 41.85)]);
      await open(t, first);
      first.config.complete(feedOn);
      await t.pumpAndSettle();

      final second = _SlowRepo(sections: feedOn, dishes: [_d('osh', lat: 41.85)]); // созлама ҳали келмаган
      await open(t, second);
      await t.pump();
      expect(find.byKey(const ValueKey('section-feed')), findsOneWidget, reason: 'лента чипи дарров');
      expect(second.listStreams, 0, reason: 'рўйхат чизилмади');
      expect(find.text(tr('restaurants_sort_distance')), findsNothing);
      second.config.complete(feedOn);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_osh')), findsOneWidget);
    });

    testWidgets('лента ўчиқ бўлса: созлама келгач ресторанлар рўйхати (аввалгидек), юкланиш белгисидан кейин', (t) async {
      final repo = _SlowRepo(sections: RestaurantSectionsConfig.off, dishes: const []);
      await open(t, repo);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.config.complete(RestaurantSectionsConfig.off);
      await t.pumpAndSettle();
      expect(find.text('Gurlan osh'), findsWidgets);
      expect(find.text(tr('restaurants_sort_distance')), findsOneWidget);
    });
  });
}