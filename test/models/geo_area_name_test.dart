import 'package:ava_gurlan/core/widgets/service_area_picker.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:ava_gurlan/repositories/service_config_repository.dart';
import 'package:ava_gurlan/utils/locale_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bug (2026-10-11): рус тили танланганда «Тил ва ҳудуд» экрани вилоят/туман
/// номларини ўзбек кириллида кўрсатарди («Сирғали тумани»).
void main() {
  group('geoNameFor', () {
    String n(String lang, {String name = '', String uz = '', String ru = ''}) =>
        geoNameFor(lang, name: name, nameUz: uz, nameRu: ru);

    test('ru → nameRu', () {
      expect(
        n('ru', name: 'Sirgʻali tumani', uz: 'Сирғали тумани', ru: 'Сергелийский район'),
        'Сергелийский район',
      );
    });

    test('ru, nameRu йўқ (эски ҳужжат) → кирилл, у ҳам йўқ → лотин', () {
      expect(n('ru', name: 'Gurlan tumani', uz: 'Гурлан тумани'), 'Гурлан тумани');
      expect(n('ru', name: 'Gurlan tumani'), 'Gurlan tumani');
    });

    test('uz_Latn → name (лотин); бўш бўлса кирилл', () {
      expect(n('uz_Latn', name: 'Gurlan tumani', uz: 'Гурлан тумани', ru: 'Гурленский район'),
          'Gurlan tumani');
      expect(n('uz_Latn', uz: 'Гурлан тумани'), 'Гурлан тумани');
    });

    test('uz_Cyrl ва номаълум код → кирилл (олдинги хулқ)', () {
      expect(n('uz_Cyrl', name: 'Gurlan tumani', uz: 'Гурлан тумани', ru: 'Гурленский район'),
          'Гурлан тумани');
      expect(n('en', name: 'Gurlan tumani', uz: 'Гурлан тумани'), 'Гурлан тумани');
    });

    test('displayName ўзгармади — доим кирилл (сақланадиган ёрлиқлар учун)', () {
      const d = GeoDistrict(
        id: 'sirgali',
        regionId: 'toshkent_shahri',
        name: 'Sirgʻali tumani',
        nameUz: 'Сирғали тумани',
        nameRu: 'Сергелийский район',
      );
      expect(d.displayName, 'Сирғали тумани');
      expect(d.nameFor('ru'), 'Сергелийский район');
      expect(d.toMap()['nameRu'], 'Сергелийский район');
      expect(const GeoRegion(id: 'x', name: 'X').toMap().containsKey('nameRu'), isFalse);
    });
  });

  test('LocaleUtils.contentLangCode', () {
    expect(LocaleUtils.contentLangCode(LocaleUtils.ru), 'ru');
    expect(LocaleUtils.contentLangCode(LocaleUtils.uzLatn), 'uz_Latn');
    expect(LocaleUtils.contentLangCode(LocaleUtils.uzCyrl), 'uz_Cyrl');
    expect(LocaleUtils.contentLangCode(const Locale('uz')), 'uz_Cyrl');
  });

  group('ServiceAreaPicker номлари тилга қараб', () {
    Future<void> pump(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: LocaleUtils.supportedAppLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ServiceAreaPicker(
            repository: _FakeRepo(),
            initialRegionId: 'toshkent_shahri',
            initialDistrictId: 'sirgali',
            showAreaDropdown: false,
            onChanged: (_, __, ___) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('ru → русча номлар (bug қайта ҳосил қилинган ҳол)', (tester) async {
      await pump(tester, LocaleUtils.ru);
      expect(find.text('город Ташкент'), findsOneWidget);
      expect(find.text('Сергелийский район'), findsOneWidget);
      expect(find.text('Тошкент шаҳри'), findsNothing);
      expect(find.text('Сирғали тумани'), findsNothing);
    });

    testWidgets('uz_Latn → лотин номлар', (tester) async {
      await pump(tester, LocaleUtils.uzLatn);
      expect(find.text('Toshkent shahri'), findsOneWidget);
      expect(find.text('Sirgʻali tumani'), findsOneWidget);
    });

    testWidgets('uz_Cyrl → кирилл номлар (олдингидек)', (tester) async {
      await pump(tester, LocaleUtils.uzCyrl);
      expect(find.text('Тошкент шаҳри'), findsOneWidget);
      expect(find.text('Сирғали тумани'), findsOneWidget);
    });
  });
}

class _FakeRepo implements ServiceConfigRepository {
  @override
  Future<List<GeoRegion>> fetchRegions({bool activeOnly = true}) async => const [
        GeoRegion(
          id: 'toshkent_shahri',
          name: 'Toshkent shahri',
          nameUz: 'Тошкент шаҳри',
          nameRu: 'город Ташкент',
        ),
        // nameRu йўқ — эски ҳужжат.
        GeoRegion(id: 'xorazm', name: 'Xorazm', nameUz: 'Хоразм'),
      ];

  @override
  Future<List<GeoDistrict>> fetchDistricts(String regionId, {bool activeOnly = true}) async =>
      const [
        GeoDistrict(
          id: 'sirgali',
          regionId: 'toshkent_shahri',
          name: 'Sirgʻali tumani',
          nameUz: 'Сирғали тумани',
          nameRu: 'Сергелийский район',
        ),
      ];

  @override
  Future<List<ServiceArea>> fetchServiceAreas(String districtId, {bool activeOnly = true}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
