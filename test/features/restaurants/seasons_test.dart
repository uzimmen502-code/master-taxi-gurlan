// Мавсумий бўлимлар, Офис ва Дастурхон, Рамазон жадвали (S7, D-REST-21/22/39): домен қоидалари (серверда
// `functions/test/restaurant_seasons.test.js` билан БИР ХИЛ векторлар), бўлим кўриниши, рўйхат дарвозаси, теглар,
// 3 тил. Ҳақиқий сана/индекс ҳисоби — серверда.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/cuisine.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_facts.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:ava_gurlan/features/restaurants/domain/seasons.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/section_dishes_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

const _lat = 41.8406;
const _lng = 60.3917;

DateTime _utc(String iso, [int hh = 12]) => DateTime.parse('${iso}T${hh.toString().padLeft(2, '0')}:00:00Z');

SectionDish _d(String id, {List<String> seasons = const [], List<String> tags = const [], int? servings, String rest = 'r1'}) => SectionDish(
      restaurantId: rest,
      itemId: id,
      name: 'Taom $id',
      price: 40000,
      restaurantName: 'Rest $rest',
      servings: servings,
      seasons: seasons,
      tags: tags,
      listedAt: DateTime(2020),
      restaurantLat: 41.8586,
      restaurantLng: 60.3917,
    );

class _Repo implements RestaurantsRepository {
  _Repo({this.dishes = const [], this.sections = RestaurantSectionsConfig.off, this.seasons = RestaurantSeasonsConfig.none, this.ramadan = RamadanConfig.none, this.seasonsFail = false});

  final List<SectionDish> dishes;
  final RestaurantSectionsConfig sections;
  final RestaurantSeasonsConfig seasons;
  final RamadanConfig ramadan;
  final bool seasonsFail;

  @override
  Future<SectionDishesResult> fetchSectionDishes(RestaurantSection section, {required double lat, required double lng, int limit = 200}) async =>
      SectionDishesResult([for (final d in dishes) d]);

  @override
  Future<RestaurantSectionsConfig> getSectionsConfig({bool force = false}) async => sections;

  @override
  Future<RestaurantSeasonsConfig> getSeasonsConfig({bool force = false}) async {
    if (seasonsFail) throw StateError('offline');
    return seasons;
  }

  @override
  Future<RamadanConfig> getRamadanConfig({bool force = false}) async => ramadan;

  @override
  Future<List<Cuisine>> listCuisines({bool force = false}) async => const [];

  @override
  Stream<List<Restaurant>> watchNearby({required double lat, required double lng, double radiusKm = 20, int perCellLimit = 50}) => Stream.value(const []);

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('RestaurantSeasonsConfig.activeAt (serverdagi activeSeasons bilan BIR XIL vektorlar)', () {
    const ramadan = RestaurantSeasonsConfig(periods: [SeasonPeriod(key: 'ramadan', from: '2027-02-08', to: '2027-03-08')]);
    List<String> at(RestaurantSeasonsConfig c, String iso, [int hh = 12]) => c.activeAt(_utc(iso, hh)).map((s) => s.key).toList();

    test('sanadan 10 kun OLDIN ochiladi, 11-kunda yopiq; oxirgi kun ochiq, ertasi yopiq', () {
      expect(at(ramadan, '2027-01-28'), isEmpty);
      expect(at(ramadan, '2027-01-29'), ['ramadan']);
      expect(at(ramadan, '2027-02-08'), ['ramadan']);
      expect(at(ramadan, '2027-03-08'), ['ramadan']);
      expect(at(ramadan, '2027-03-09'), isEmpty);
      expect(ramadan.activeAt(_utc('2027-01-29')).single.opensOn, '2027-01-29');
    });

    test('opensDaysBefore=0 — faqat davr ichida', () {
      const zero = RestaurantSeasonsConfig(periods: [SeasonPeriod(key: 'ramadan', from: '2027-02-08', to: '2027-03-08')], opensDaysBefore: 0);
      expect(at(zero, '2027-01-31'), isEmpty);
      expect(at(zero, '2027-02-08'), ['ramadan']);
    });

    test('Toshkent kuni bo\'yicha: UTC 19:00 = ertasi kun; bir nechta mavsum SeasonKey tartibida; bo\'sh/buzilgan — hech narsa', () {
      const cfg = RestaurantSeasonsConfig(periods: [
        SeasonPeriod(key: 'ramadan', from: '2027-02-09', to: '2027-03-15', confirmed: true),
        SeasonPeriod(key: 'navruz', from: '2027-03-21', to: '2027-03-21'),
        SeasonPeriod(key: 'wedding', from: '2027-03-01', to: '2027-04-30', confirmed: true),
      ]);
      expect(cfg.activeAt(DateTime.parse('2027-01-29T19:00:00Z')).map((s) => s.key), ['ramadan']);
      expect(cfg.activeAt(DateTime.parse('2027-01-29T18:00:00Z')), isEmpty);
      expect(at(cfg, '2027-03-12'), ['ramadan', 'navruz', 'wedding']);
      expect(at(cfg, '2027-03-05'), ['ramadan', 'wedding'], reason: 'Navro\'z 11 martda ochiladi (21 − 10)');
      expect(at(RestaurantSeasonsConfig.none, '2027-03-05'), isEmpty);
      expect(at(const RestaurantSeasonsConfig(periods: [SeasonPeriod(key: 'ramadan', from: 'x', to: 'y')]), '2027-03-05'), isEmpty);
    });

    test('fromMap: buzilgan davrlar tashlanadi; noma\'lum kalit, mavjud bo\'lmagan sana, opens chegarasi', () {
      final c = RestaurantSeasonsConfig.fromMap({
        'version': 3,
        'opensDaysBefore': 7,
        'periods': [
          {'key': 'ramadan', 'from': '2027-02-09', 'to': '2027-03-09', 'confirmed': true},
          {'key': 'eid', 'from': '2027-05-16', 'to': '2027-05-19'},
          {'key': 'qurbon', 'from': '2027-02-30', 'to': '2027-05-19'},
          'x',
        ],
      });
      expect([c.version, c.opensDaysBefore, c.periods.length], [3, 7, 1]);
      expect(c.periods.single.confirmed, isTrue);
      for (final bad in [31, -1, 1.5, '10', null]) {
        expect(RestaurantSeasonsConfig.fromMap({'opensDaysBefore': bad}).opensDaysBefore, RestaurantSeasonsConfig.defaultOpensDaysBefore, reason: '$bad');
      }
      expect(RestaurantSeasonsConfig.fromMap(null).periods, isEmpty);
    });

    test('tashkentDay: UTC+5', () {
      expect(tashkentDay(DateTime.parse('2027-02-08T18:59:00Z')), '2027-02-08');
      expect(tashkentDay(DateTime.parse('2027-02-08T19:00:00Z')), '2027-02-09');
    });
  });

  group('RamadanConfig.timesFor (serverdagi ramadanTimesFor bilan BIR XIL vektorlar)', () {
    final cfg = RamadanConfig.fromMap({
      'days': {
        '2027-02-09': {'sahar': '05:51', 'iftar': '18:02'},
        '2027-02-10': {'sahar': '00:10', 'iftar': '23:50'},
        '2027-02-30': {'sahar': '05:51', 'iftar': '18:02'},
        '2027-02-11': {'sahar': '5:51', 'iftar': '18:02'},
      },
      'offsets': {'toshkent': 0, 'nukus': 42, 'andijon': -11, 'bad': 500, 'x': 1.5},
    });

    test('Toshkent + farq (Nukus +42, Andijon −11); yarim tundan o\'tishi', () {
      expect((cfg.timesFor('2027-02-09', 'toshkent')!.sahar, cfg.timesFor('2027-02-09', 'toshkent')!.iftar), ('05:51', '18:02'));
      expect((cfg.timesFor('2027-02-09', 'nukus')!.sahar, cfg.timesFor('2027-02-09', 'nukus')!.iftar), ('06:33', '18:44'));
      expect((cfg.timesFor('2027-02-09', 'andijon')!.sahar, cfg.timesFor('2027-02-09', 'andijon')!.iftar), ('05:40', '17:51'));
      expect((cfg.timesFor('2027-02-10', 'nukus')!.sahar, cfg.timesFor('2027-02-10', 'nukus')!.iftar), ('00:52', '00:32'));
      expect((cfg.timesFor('2027-02-10', 'andijon')!.sahar, cfg.timesFor('2027-02-10', 'andijon')!.iftar), ('23:59', '23:39'));
    });

    test('hudud/kun jadvalda yo\'q yoki buzilgan — null (vaqt TAXMIN QILINMAYDI)', () {
      expect(cfg.timesFor('2027-02-09', 'samarqand'), isNull);
      expect(cfg.timesFor('2027-02-11', 'toshkent'), isNull, reason: 'kun jadvalda yo\'q');
      expect(cfg.timesFor('2027-02-09', ''), isNull);
      expect(cfg.timesFor('2027-02-09', null), isNull);
      expect(cfg.timesFor('2027-02-09', 'bad'), isNull, reason: 'farq −120..120 dan tashqarida — jadvalga kirmagan');
      expect(cfg.timesFor('2027-02-09', 'x'), isNull, reason: 'kasr farq');
      expect(RamadanConfig.none.timesFor('2027-02-09', 'toshkent'), isNull);
      expect(cfg.days.containsKey('2027-02-30'), isFalse);
    });
  });

  group('Teglar va bo\'limlar: SERVER bilan moslik', () {
    final server = File('functions/restaurant_dish_index.js').readAsStringSync();
    final rules = File('firestore.rules').readAsStringSync();

    test('DishTag.all = serverdagi DISH_TAGS = rules tags.hasOnly', () {
      final seasonKeys = RegExp(r"SEASON_KEYS = Object\.freeze\(\[([^\]]*)\]").firstMatch(server)![1]!.split(',').map((s) => s.trim().replaceAll("'", '')).toList();
      expect(DishTag.seasons, seasonKeys);
      expect(seasonKeys, SeasonKey.all);
      final dish = RegExp(r"DISH_TAGS = Object\.freeze\(\[([^\]]*)\]").firstMatch(server)![1]!;
      expect(dish.contains('...SEASON_KEYS'), isTrue);
      for (final t in DishTag.all) {
        expect(server.contains("'$t'") || seasonKeys.contains(t) || dish.contains(t.toUpperCase()), isTrue, reason: t);
      }
      final hasOnly = RegExp(r"d\.tags\.hasOnly\(\[([^\]]*)\]").firstMatch(rules)![1]!.split(',').map((s) => s.trim().replaceAll("'", '')).where((s) => s.isNotEmpty).toList();
      expect(hasOnly.toSet(), DishTag.all.toSet());
      expect(RegExp(r'MAX_TAGS_PER_DISH = (\d+)').firstMatch(server)![1], '${DishTag.maxPerDish}');
      expect(rules.contains('d.tags.size() <= ${DishTag.maxPerDish}'), isTrue);
    });

    test('bo\'lim kalitlari: enum = serverdagi SECTION (13 ta, all lentasi va home bilan)', () {
      final block = RegExp(r'const SECTION = Object\.freeze\(\{([^}]*)\}', dotAll: true).firstMatch(server)![1]!;
      final keys = RegExp(r"(\w+): '(\w+)'").allMatches(block).map((m) => m[2]!).toSet();
      expect(RestaurantSection.values.map((s) => s.key).toSet(), keys);
      expect(keys.length, 13);
    });

    test('Ofis/Dastarxon — oldindan buyurtmaga tayanadi, Mavsumiy — mavsum filtri', () {
      expect(RestaurantSection.office.isPreorderBased, isTrue);
      expect(RestaurantSection.dastarxon.isPreorderBased, isTrue);
      expect(RestaurantSection.cheap.isPreorderBased, isFalse);
      expect(RestaurantSection.seasonal.hasSeasonFilter, isTrue);
      expect(RestaurantSection.national.hasSeasonFilter, isFalse);
      expect(SectionDish.fromMap({'seasons': ['ramadan', 5, 'navruz']}).seasons, ['ramadan', 'navruz']);
      expect(SectionDish.fromMap(const {}).seasons, isEmpty, reason: 'eski indeks hujjati');
    });
  });

  group('SectionDishesView: Mavsumiy / Ofis / Dastarxon', () {
    Future<void> pumpView(WidgetTester t, _Repo repo, RestaurantSection section,
        {List<ActiveSeason> seasons = const [], RamadanConfig ramadan = RamadanConfig.none, String? region, double width = 390, double scale = 1.0}) async {
      t.view.physicalSize = Size(width * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        textScale: scale,
        home: Scaffold(
          body: SectionDishesView(
            key: UniqueKey(),
            section: section,
            config: const RestaurantSectionsConfig(),
            repository: repo,
            lat: _lat,
            lng: _lng,
            now: () => DateTime.parse('2027-02-09T08:00:00Z'),
            seasons: seasons,
            ramadan: ramadan,
            regionId: region,
            onOpenRestaurant: (_) {},
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    const open = [
      ActiveSeason(key: 'ramadan', from: '2027-02-09', to: '2027-03-09', confirmed: true, opensOn: '2027-01-30'),
      ActiveSeason(key: 'wedding', from: '2027-02-01', to: '2027-04-30', confirmed: true, opensOn: '2027-01-22'),
    ];
    final ramadanTimes = RamadanConfig.fromMap({
      'days': {'2027-02-09': {'sahar': '05:51', 'iftar': '18:02'}},
      'offsets': {'toshkent': 0, 'nukus': 42},
    });

    testWidgets('faqat HOZIR ochiq mavsum tegli taomlar; boshqa mavsum (navruz) taomi ko\'rinmaydi', (t) async {
      final repo = _Repo(dishes: [_d('a', seasons: ['ramadan']), _d('b', seasons: ['wedding']), _d('c', seasons: ['navruz']), _d('d')]);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open);
      expect(find.byKey(const ValueKey('dish-r1_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-r1_b')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-r1_c')), findsNothing, reason: 'Navro\'z hali ochilmagan');
      expect(find.byKey(const ValueKey('dish-r1_d')), findsNothing);
    });

    testWidgets('bir nechta mavsum ochiq: mavsum chiplari (sonlari bilan); tanlansa faqat shu mavsum, «Hammasi» qaytaradi', (t) async {
      final repo = _Repo(dishes: [_d('a', seasons: ['ramadan']), _d('b', seasons: ['wedding']), _d('e', seasons: ['wedding'])]);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open, width: 800);
      expect(find.byKey(const ValueKey('season-chips')), findsOneWidget);
      expect(find.text('${tr('restaurants_season_ramadan')} · 1'), findsOneWidget);
      expect(find.text('${tr('restaurants_season_wedding')} · 2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('season-wedding')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_a')), findsNothing);
      expect(find.byKey(const ValueKey('dish-r1_b')), findsOneWidget);
      await t.tap(find.text(tr('restaurants_cuisine_all')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-r1_a')), findsOneWidget);
    });

    testWidgets('bitta mavsum ochiq: chiplar yo\'q; taomi yo\'q mavsum chipi ko\'rinmaydi', (t) async {
      final repo = _Repo(dishes: [_d('a', seasons: ['ramadan'])]);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open);
      expect(find.byKey(const ValueKey('season-chips')), findsNothing, reason: 'faqat Ramazonda taom bor — bitta chip ma\'nosiz');
    });

    testWidgets('Ramazon: bugungi saharlik/iftor — hudud jadvalda bo\'lsa (Toshkent 18:02, Nukus +42 = 18:44)', (t) async {
      final repo = _Repo(dishes: [_d('a', seasons: ['ramadan'])]);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open, ramadan: ramadanTimes, region: 'nukus');
      final text = (t.widget(find.descendant(of: find.byKey(const ValueKey('ramadan-times')), matching: find.byType(Text))) as Text).data!;
      expect(text, tr('restaurants_ramadan_today').replaceAll('{sahar}', '06:33').replaceAll('{iftar}', '18:44'));
    });

    testWidgets('Ramazon vaqti ko\'rsatilmaydi: hudud jadvalda yo\'q / hudud noma\'lum / Ramazon ochiq emas', (t) async {
      final repo = _Repo(dishes: [_d('a', seasons: ['ramadan']), _d('b', seasons: ['wedding'])]);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open, ramadan: ramadanTimes, region: 'samarqand');
      expect(find.byKey(const ValueKey('ramadan-times')), findsNothing);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open, ramadan: ramadanTimes, region: null);
      expect(find.byKey(const ValueKey('ramadan-times')), findsNothing);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: [open[1]], ramadan: ramadanTimes, region: 'nukus');
      expect(find.byKey(const ValueKey('ramadan-times')), findsNothing, reason: 'Ramazon mavsumi ochiq emas');
    });

    testWidgets('Ofis va Dastarxon: kartada «Oldindan buyurtma»; Dastarxonda «N kishi uchun»; boshqa bo\'limda yo\'q', (t) async {
      final repo = _Repo(dishes: [_d('a', servings: 6)]);
      await pumpView(t, repo, RestaurantSection.dastarxon);
      expect(find.byKey(const ValueKey('pre-r1_a')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('serves-r1_a'))) as Text).data, tr('restaurants_dish_serves').replaceAll('{n}', '6'));
      await pumpView(t, repo, RestaurantSection.office);
      expect(find.byKey(const ValueKey('pre-r1_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('serves-r1_a')), findsNothing);
      await pumpView(t, repo, RestaurantSection.kids);
      expect(find.byKey(const ValueKey('pre-r1_a')), findsNothing);
    });

    testWidgets('tor ekran 320 + shrift ×2: mavsumiy bo\'lim overflow qilmaydi', (t) async {
      final repo = _Repo(dishes: [_d('a', seasons: ['ramadan']), _d('b', seasons: ['wedding'])]);
      await pumpView(t, repo, RestaurantSection.seasonal, seasons: open, ramadan: ramadanTimes, region: 'nukus', width: 320, scale: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('RestaurantsListScreen: mavsumiy chip dastlab yashirin', () {
    const sectionsAll = RestaurantSectionsConfig(stages: {'seasonal': 'public', 'office': 'public', 'dastarxon': 'public'});

    Future<void> pumpList(WidgetTester t, _Repo repo) async {
      // Кенг экран: горизонтал чиплар рўйхати ленивый — ҳаммаси қурилсин.
      t.view.physicalSize = const Size(2400 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantsListScreen(key: UniqueKey(), repository: repo, currentUid: '998912000001', userLat: _lat, userLng: _lng, locate: () async => null),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('mavsum chipi: bo\'lim yoqilgan VA hozir ochiq mavsum bor bo\'lsagina; Ofis/Dastarxon — yoqilgan bo\'lsa', (t) async {
      final openCfg = RestaurantSeasonsConfig(periods: [
        SeasonPeriod(key: 'ramadan', from: tashkentDay(DateTime.now().add(const Duration(days: 3))), to: tashkentDay(DateTime.now().add(const Duration(days: 30)))),
      ]);
      await pumpList(t, _Repo(sections: sectionsAll, seasons: openCfg));
      expect(find.byKey(const ValueKey('section-seasonal')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-office')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-dastarxon')), findsOneWidget);
      await pumpList(t, _Repo(sections: sectionsAll, seasons: RestaurantSeasonsConfig.none));
      expect(find.byKey(const ValueKey('section-seasonal')), findsNothing, reason: 'ochiq mavsum yo\'q');
      expect(find.byKey(const ValueKey('section-office')), findsOneWidget);
      await pumpList(t, _Repo(sections: sectionsAll, seasonsFail: true));
      expect(find.byKey(const ValueKey('section-seasonal')), findsNothing, reason: 'sozlama o\'qilmadi — yashirin');
      expect(t.takeException(), isNull);
      await pumpList(t, _Repo(sections: const RestaurantSectionsConfig(stages: {'office': 'public'}), seasons: openCfg));
      expect(find.byKey(const ValueKey('section-seasonal')), findsNothing, reason: 'bo\'lim OFF');
    });
  });

  group('3 tilda matnlar', () {
    Map<String, dynamic> load(String n) => jsonDecode(File('assets/lang/$n.json').readAsStringSync()) as Map<String, dynamic>;
    final cyrl = load('uz_Cyrl');
    final latn = load('uz_Latn');
    final ru = load('ru');
    final keys = <String>[
      'restaurants_section_office', 'restaurants_section_dastarxon', 'restaurants_section_seasonal',
      'restaurants_ramadan_today', 'restaurants_dish_preorder', 'restaurants_dish_serves',
      for (final t in [DishTag.dastarxon, ...DishTag.seasons]) 'restaurants_m_dish_tag_$t',
      for (final s in SeasonKey.all) 'restaurants_season_$s',
    ];

    test('har kalit uchala tilda bor, bo\'sh emas, parametrlar bir xil; lotinda kirill, kirill/rusda lotin so\'z va rusda ў қ ғ ҳ yo\'q', () {
      final ph = RegExp(r'\{(\w+)\}');
      final cyr = RegExp(r'[Ѐ-ӿ]');
      final lat = RegExp(r'[A-Za-z]{2,}');
      final uz = RegExp('[ўқғҳЎҚҒҲ]');
      for (final k in keys) {
        for (final m in [cyrl, latn, ru]) {
          expect((m[k] as String?)?.trim().isNotEmpty, isTrue, reason: k);
        }
        Set<String> p(Map<String, dynamic> m) => ph.allMatches(m[k] as String).map((x) => x[1]!).toSet();
        expect(p(latn), p(cyrl), reason: k);
        expect(p(ru), p(cyrl), reason: k);
        expect(cyr.hasMatch(latn[k] as String), isFalse, reason: 'latn $k');
        for (final m in [cyrl, ru]) {
          expect(lat.hasMatch((m[k] as String).replaceAll(RegExp(r'\{\w+\}'), '')), isFalse, reason: 'cyr/ru $k');
        }
        expect(uz.hasMatch(ru[k] as String), isFalse, reason: 'ru $k');
      }
      expect(tr('restaurants_section_seasonal'), isNotEmpty);
    });
  });
}
