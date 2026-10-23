// Бўлимлар экрани (S3, D-REST-33): таомлар рўйхати, «Янги» белгиси, кухна фильтри, ҳолатлар ва
// «Барчаси» экранидаги бўлим чиплари (дарвоза: созлама ҳужжати йўқ/ўчиқ — экран аввалгидек).

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_stats.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/section_dishes_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

const _lat = 41.8406;
const _lng = 60.3917;
final _now = DateTime(2026, 10, 19, 12);

SectionDish _d(
  String id, {
  String rest = 'r1',
  int price = 40000,
  int? pp,
  int sum = 0,
  int count = 0,
  int? listedDaysAgo = 90,
  int prep = 25,
  String? cuisine,
  int? kcal,
  DateTime? paused,
  String name = '',
}) =>
    SectionDish(
      restaurantId: rest,
      itemId: id,
      name: name.isEmpty ? 'Taom $id' : name,
      price: price,
      pricePerPerson: pp,
      restaurantName: 'Rest $rest',
      ratingSum: sum,
      ratingCount: count,
      prepTimeMin: prep,
      cuisineId: cuisine,
      cuisineGroup: cuisine == null ? null : 'national',
      kcal: kcal,
      listedAt: listedDaysAgo == null ? null : _now.subtract(Duration(days: listedDaysAgo)),
      pausedUntil: paused,
      restaurantLat: 41.8586,
      restaurantLng: 60.3917,
    );

class _Repo implements RestaurantsRepository {
  _Repo({
    this.dishes = const [],
    this.truncated = false,
    this.config = RestaurantSectionsConfig.off,
    this.cuisines = const [],
    this.failFetch = 0,
  });

  List<SectionDish> dishes;
  final bool truncated;
  final RestaurantSectionsConfig config;
  final List<Cuisine> cuisines;
  int failFetch;
  final fetched = <RestaurantSection>[];
  final opened = <String>[];

  @override
  Future<SectionDishesResult> fetchSectionDishes(RestaurantSection section, {required double lat, required double lng, int limit = 200}) async {
    fetched.add(section);
    if (failFetch > 0) {
      failFetch -= 1;
      throw StateError('offline');
    }
    return SectionDishesResult([for (final d in dishes) d], truncated: truncated);
  }

  @override
  Future<RestaurantSectionsConfig> getSectionsConfig({bool force = false}) async => config;

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => cuisines;

  @override
  Stream<List<Restaurant>> watchNearby({required double lat, required double lng, double radiusKm = 20, int perCellLimit = 50}) =>
      Stream.value(const [Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved')]);

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(const []);

  @override
  Future<Restaurant?> getRestaurant(String id) async =>
      id == 'missing' ? null : Restaurant(id: id, name: 'Rest $id', status: 'approved');

  /// Таом ҳужжати: `gone` дан бошланган идентификатор — ўчирилган таом (null).
  @override
  Future<MenuItem?> getMenuItem(String restaurantId, String itemId) async =>
      itemId.startsWith('gone') ? null : MenuItem(id: itemId, name: 'Tafsilot $itemId', price: 40000, description: 'To\'liq tavsif $itemId');

  @override
  Future<DishStats> getDishStat(String restaurantId, String itemId) async => DishStats.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // «Охирги маълум созлама» (экран очилишини тезлатади) тестлар орасида эскирмасин.
  setUp(RestaurantsListScreen.resetLastKnownConfig);
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  Future<void> pumpView(
    WidgetTester t,
    _Repo repo,
    RestaurantSection section, {
    double? lat = _lat,
    double? lng = _lng,
    void Function(String)? onOpen,
    double width = 390,
    double textScale = 1.0,
    RestaurantSectionsConfig config = const RestaurantSectionsConfig(),
  }) async {
    t.view.physicalSize = Size(width * 3, 1800 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(l10nApp(
      textScale: textScale,
      home: Scaffold(
        body: SectionDishesView(
          key: UniqueKey(), // ҳар чақирувда ЯНГИ ҳолат
          section: section,
          config: config,
          repository: repo,
          lat: lat,
          lng: lng,
          now: () => _now,
          onOpenDish: (d) => onOpen?.call(d.restaurantId),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  group('SectionDishesView', () {
    testWidgets('«Арзон»: «Янги» тепада (белги билан), кейин рейтинги чегарадан кам бўлмаганлар; бир кишилик нарх асосий', (t) async {
      final repo = _Repo(dishes: [
        _d('low', pp: 4000, price: 16000),
        _d('top', pp: 7000, price: 28000, sum: 25, count: 5),
        _d('fresh', rest: 'r2', pp: 12000, price: 48000, listedDaysAgo: 1),
      ]);
      await pumpView(t, repo, RestaurantSection.cheap);
      expect(t.takeException(), isNull);
      final order = [for (final id in ['r2_fresh', 'r1_top', 'r1_low']) t.getTopLeft(find.byKey(ValueKey('dish-$id'))).dy];
      expect(order, [...order]..sort(), reason: 'Янги → юқори поғона → қолганлар');
      expect(find.byKey(const ValueKey('new-r2_fresh')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-r1_top')), findsNothing);
      expect(find.byKey(const ValueKey('pp-r1_top')), findsOneWidget);
      expect(find.textContaining(tr('restaurants_dish_per_person').split('{price}').first), findsWidgets);
      expect((t.widget(find.byKey(const ValueKey('rating-r1_top'))) as Text).data, '5.0 (5)');
      expect(find.byKey(const ValueKey('rating-r1_low')), findsNothing, reason: 'баҳоси йўқ — юлдуз йўқ');
      expect(repo.fetched, [RestaurantSection.cheap]);
    });

    testWidgets('«Фаст-фуд»: тайёрлаш вақти кўрсатилади; «Парҳезли овқатлар»: ккал; бошқа бўлимда бундай чиплар йўқ', (t) async {
      final repo = _Repo(dishes: [_d('a', prep: 12, kcal: 420)]);
      await pumpView(t, repo, RestaurantSection.fast);
      expect(find.byKey(const ValueKey('prep-r1_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('kcal-r1_a')), findsNothing);
      await pumpView(t, repo, RestaurantSection.light);
      expect(find.byKey(const ValueKey('kcal-r1_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('prep-r1_a')), findsNothing);
      await pumpView(t, repo, RestaurantSection.kids);
      expect(find.byKey(const ValueKey('kcal-r1_a')), findsNothing);
      expect(find.byKey(const ValueKey('prep-r1_a')), findsNothing);
    });

    testWidgets('ёпиқ ресторан таоми: «Ёпиқ» ёрлиғи ва охирида; босилса барибир ресторан очилади', (t) async {
      final opened = <String>[];
      final repo = _Repo(dishes: [
        _d('c', rest: 'rc', paused: _now.add(const Duration(hours: 1))),
        _d('o', rest: 'ro', sum: 25, count: 5),
      ]);
      await pumpView(t, repo, RestaurantSection.kids, onOpen: opened.add);
      expect(find.textContaining(tr('restaurants_closed')), findsOneWidget, reason: '«Ёпиқ» ёрлиғи ресторан сатрида');
      // 2 устунли катакда: очиқ ресторан таоми олдин (қатор бир хил бўлса — чапда).
      final o = t.getTopLeft(find.byKey(const ValueKey('dish-ro_o')));
      final c = t.getTopLeft(find.byKey(const ValueKey('dish-rc_c')));
      expect(o.dy < c.dy || (o.dy == c.dy && o.dx < c.dx), isTrue);
      await t.tap(find.byKey(const ValueKey('dish-rc_c')));
      expect(opened, ['rc']);
    });

    testWidgets('«Миллий»: кухна чиплари фақат таоми борлар билан; танланса фильтр, «Ҳаммаси» қайтаради; битта кухна — чип йўқ', (t) async {
      const cuisines = [
        Cuisine(id: 'a', name: 'Узбек', group: 'national', names: {'uz_Latn': "O'zbek"}),
        Cuisine(id: 'b', name: 'Хоразм', group: 'national', names: {'uz_Latn': 'Xorazm'}),
        Cuisine(id: 'c', name: 'Бўш', group: 'national', names: {'uz_Latn': "Bo'sh"}),
      ];
      final repo = _Repo(cuisines: cuisines, dishes: [
        _d('1', cuisine: 'a', sum: 25, count: 5),
        _d('2', cuisine: 'a', sum: 20, count: 5),
        _d('3', cuisine: 'b', sum: 25, count: 5),
        _d('4'),
      ]);
      await pumpView(t, repo, RestaurantSection.national);
      expect(find.byKey(const ValueKey('cuisine-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('cuisine-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('cuisine-c')), findsNothing, reason: 'таоми йўқ кухна чиқмайди');
      expect(find.textContaining("O'zbek · 2"), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-r1_4')), findsOneWidget);

      await t.drag(find.byKey(const ValueKey('cuisine-chips')), const Offset(-200, 0)); // чиплар қатори горизонтал сурилади
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cuisine-b')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_3')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-r1_1')), findsNothing);
      expect(find.byKey(const ValueKey('dish-r1_4')), findsNothing, reason: 'кухнасиз таом фильтрда йўқ');

      await t.tap(find.byKey(const ValueKey('cuisine-b'))); // қайта босиш — олиб ташлайди
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_1')), findsOneWidget);

      final single = _Repo(cuisines: cuisines, dishes: [_d('1', cuisine: 'a')]);
      await pumpView(t, single, RestaurantSection.national);
      expect(find.byKey(const ValueKey('cuisine-chips')), findsNothing, reason: 'битта кухна — фильтр маъносиз');
    });

    testWidgets('бўш рўйхат, чекланган рўйхат огоҳлантириши, жойлашув йўқ', (t) async {
      await pumpView(t, _Repo(), RestaurantSection.cheap);
      expect(find.text(tr('restaurants_dish_empty')), findsOneWidget);
      await pumpView(t, _Repo(dishes: [_d('a')], truncated: true), RestaurantSection.cheap);
      expect(find.text(tr('restaurants_dish_truncated')), findsOneWidget);
      final repo = _Repo(dishes: [_d('a')]);
      await pumpView(t, repo, RestaurantSection.cheap, lat: null, lng: null);
      expect(find.text(tr('restaurants_dish_no_location')), findsOneWidget);
      expect(repo.fetched, isEmpty, reason: 'координатасиз сўров юборилмайди');
    });

    testWidgets('хато: огоҳлантириш ва «қайта уриниш»; муваффақиятли қайта юклаш рўйхатни кўрсатади', (t) async {
      final repo = _Repo(dishes: [_d('a')], failFetch: 1);
      await pumpView(t, repo, RestaurantSection.cheap);
      expect(find.text(tr('home_section_error')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('section-retry')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_a')), findsOneWidget);
      expect(repo.fetched.length, 2);
    });

    testWidgets('тор экран 320 + шрифт ×2: карточкалар синмайди (кухна чиплари, рейтинг, нарх қаторлари)', (t) async {
      final repo = _Repo(
        cuisines: const [Cuisine(id: 'a', name: 'Узбек', group: 'national'), Cuisine(id: 'b', name: 'Хоразм', group: 'national')],
        dishes: [
          _d('1', cuisine: 'a', pp: 8750, price: 35000, sum: 47, count: 10, name: 'Тўй оши (қозонда пиширилган, катта порция)'),
          _d('2', cuisine: 'b', listedDaysAgo: 1, pp: 5000),
        ],
      );
      await pumpView(t, repo, RestaurantSection.national, width: 320, textScale: 2.0);
      expect(t.takeException(), isNull);
      await pumpView(t, repo, RestaurantSection.cheap, width: 320, textScale: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('«Барчаси» экрани: бўлим чиплари', () {
    Future<_Repo> pumpList(WidgetTester t, _Repo repo, {String? uid = '998901234567'}) async {
      // Кенг экран: горизонтал чиплар рўйхати ленивый — ҳамма чип қурилсин.
      t.view.physicalSize = const Size(2400 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantsListScreen(
          key: UniqueKey(),
          userLat: _lat,
          userLng: _lng,
          repository: repo,
          locate: () async => null,
          currentUid: uid,
          cart: RestaurantCart(),
          onOpenRestaurant: (r) => repo.opened.add(r.id),
        ),
      ));
      await t.pumpAndSettle();
      return repo;
    }

    final publicCfg = RestaurantSectionsConfig.fromMap({
      'sections': {'home': 'public', 'national': 'internal', 'kids': 'off'},
      'testerIds': ['998901234567'],
    });

    testWidgets('созлама йўқ/ҳамма ўчиқ — чиплар УМУМАН йўқ, экран аввалгидек (feature flag)', (t) async {
      await pumpList(t, _Repo());
      expect(find.byKey(const ValueKey('section-chips')), findsNothing);
      expect(find.text(tr('restaurants_sort_distance')), findsOneWidget);
      expect(find.text('Gurlan osh'), findsOneWidget);
    });

    testWidgets('public ҳамма учун, internal — фақат синовчига; off — ҳеч кимга', (t) async {
      await pumpList(t, _Repo(config: publicCfg));
      expect(find.byKey(const ValueKey('section-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-national')), findsOneWidget, reason: 'синовчи');
      expect(find.byKey(const ValueKey('section-kids')), findsNothing);
      await pumpList(t, _Repo(config: publicCfg), uid: '998909999999');
      expect(find.byKey(const ValueKey('section-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-national')), findsNothing, reason: 'синовчи эмас');
    });

    testWidgets('бўлим босилса таомлар (ресторан рўйхати ўрнига); «Ресторанлар» қайтаради; таом босилса ресторан экрани учун ресторан олинади', (t) async {
      final repo = _Repo(config: publicCfg, dishes: [_d('a', pp: 5000, sum: 25, count: 5)]);
      await pumpList(t, repo);
      await t.tap(find.byKey(const ValueKey('section-home')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_a')), findsOneWidget);
      expect(find.text(tr('restaurants_sort_distance')), findsNothing, reason: 'бўлимда саралаш чиплари йўқ');
      expect(repo.fetched, [RestaurantSection.home]);

      await t.tap(find.byKey(const ValueKey('section-all')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_a')), findsNothing);
      expect(find.text(tr('restaurants_sort_distance')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('section-home')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-r1_a')));
      await t.pumpAndSettle();
      // Таом босилса ресторан экрани эмас, ТАОМ ТАФСИЛОТИ варағи очилади (экран қолади).
      expect(repo.opened, isEmpty, reason: 'ресторан экрани ҳали очилмади');
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsOneWidget);
      expect(find.text('Tafsilot a'), findsOneWidget);
      // «Менюни кўриш» — ресторан экрани.
      await t.tap(find.byKey(const ValueKey('dish-sheet-open-menu')));
      await t.pumpAndSettle();
      expect(repo.opened, ['r1'], reason: 'ресторан ҳужжати олинди ва экран очиш чақирилди');
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing, reason: 'варақ ёпилди');
    });

    testWidgets('таом ҳужжати ўчирилган — варақ эмас, ресторан менюси очилади (фойдаланувчи тўхтаб қолмайди)', (t) async {
      final repo = _Repo(config: publicCfg, dishes: [_d('gone1', pp: 5000)]);
      await pumpList(t, repo);
      await t.tap(find.byKey(const ValueKey('section-home')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-r1_gone1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-sheet-name')), findsNothing);
      expect(repo.opened, ['r1']);
    });

    testWidgets('бўлимда қидирув ёзилса — умумий рўйхатга қайтади; ресторан топилмаса — хабар', (t) async {
      final repo = _Repo(config: publicCfg, dishes: [_d('a', rest: 'missing', pp: 5000)]);
      await pumpList(t, repo);
      await t.tap(find.byKey(const ValueKey('section-home')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-missing_a')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_dish_open_failed')), findsOneWidget);

      await t.enterText(find.byType(TextField), 'osh');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-missing_a')), findsNothing);
      expect(find.text(tr('restaurants_sort_distance')), findsOneWidget);
    });
  });
}
