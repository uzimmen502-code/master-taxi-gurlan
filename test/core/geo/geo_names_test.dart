import 'package:ava_gurlan/core/brand_labels.dart';
import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/geo_name_text.dart';
import 'package:ava_gurlan/core/geo/geo_names.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:ava_gurlan/repositories/service_config_repository.dart';
import 'package:ava_gurlan/utils/locale_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bug (2026-10-11): рус тили танланганда сарлавҳа, профил, ҳудуд тугмаси
/// ва TV ёрлиқлари туман номини кириллда кўрсатарди (сақланган ёрлиқ).
void main() {
  late _FakeRepo repo;

  setUp(() {
    GeoNames.reset();
    repo = _FakeRepo();
    GeoNames.repository = repo;
  });

  tearDown(() {
    GeoNames.reset();
    ServiceConfigHolder.resetForTest();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('district', () {
    test('кирилл + сақланган ёрлиқ → ёрлиқ, Firestore ўқилмайди (олдинги хулқ ва нарх)', () async {
      expect(GeoNames.district('gurlan', 'uz_Cyrl', fallback: 'Гурлан'), 'Гурлан');
      await settle();
      expect(repo.districtCalls, 0);
    });

    test('рус: аввал fallback, ном келгач — nameRuShort; revision ошади', () async {
      final rev = GeoNames.revision.value;
      expect(GeoNames.district('gurlan', 'ru', fallback: 'Гурлан'), 'Гурлан');
      await settle();
      expect(GeoNames.revision.value, rev + 1);
      expect(GeoNames.district('gurlan', 'ru', fallback: 'Гурлан'), 'Гурлен');
      expect(repo.districtCalls, 1, reason: 'бир ID — бир ўқиш');
    });

    test('рус: қисқаси йўқ — «город » олиб ташланади; nameRu йўқ — кирилл қисқаси', () async {
      GeoNames.district('urganch_shahri', 'ru');
      GeoNames.district('old', 'ru');
      await settle();
      expect(GeoNames.district('urganch_shahri', 'ru'), 'Ургенч');
      expect(GeoNames.district('old', 'ru'), 'Эски');
    });

    test('лотин → «tumani»сиз лотин', () async {
      GeoNames.district('gurlan', 'uz_Latn', fallback: 'Гурлан');
      await settle();
      expect(GeoNames.district('gurlan', 'uz_Latn', fallback: 'Гурлан'), 'Gurlan');
    });

    test('remember() — ўқишсиз', () {
      GeoNames.remember(districts: [_gurlan]);
      expect(GeoNames.district('gurlan', 'ru'), 'Гурлен');
      expect(repo.districtCalls, 0);
    });

    test('ҳужжат йўқ/офлайн → fallback, дарҳол қайта ўқилмайди', () async {
      expect(GeoNames.district('nope', 'ru', fallback: 'X'), 'X');
      await settle();
      expect(GeoNames.district('nope', 'ru', fallback: 'X'), 'X');
      await settle();
      expect(repo.districtCalls, 1);
    });

    test('бўш ID → fallback, ўқиш йўқ', () async {
      expect(GeoNames.district('', 'ru', fallback: 'Гурлан'), 'Гурлан');
      await settle();
      expect(repo.districtCalls, 0);
    });
  });

  test('region + area: «Гурлен, Хорезм»; «город Ташкент» → «Ташкент»; қисқаси йўқ — тўлиқ', () async {
    GeoNames.remember(districts: [_gurlan], regions: _regions);
    const home = GeoArea(
      regionId: 'xorazm',
      districtId: 'gurlan',
      regionLabel: 'Хоразм',
      districtLabel: 'Гурлан',
    );
    expect(GeoNames.area(home, 'ru'), 'Гурлен, Хорезм');
    expect(GeoNames.area(home, 'uz_Latn'), 'Gurlan, Xorazm');
    expect(GeoNames.area(home, 'uz_Cyrl'), 'Гурлан, Хоразм');
    expect(GeoNames.region('toshkent_shahri', 'ru'), 'Ташкент');
    expect(GeoNames.region('andijon', 'ru'), 'Андижанская область');
  });

  group('виджетлар рус тилида', () {
    Widget app(Widget child) => MaterialApp(
          locale: LocaleUtils.ru,
          supportedLocales: LocaleUtils.supportedAppLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: child),
        );

    testWidgets('BrandTitleColumn: сарлавҳа «Гурлан» → «Гурлен»', (tester) async {
      ServiceConfigHolder.setForTest(
        regionId: 'xorazm',
        districtId: 'gurlan',
        regionLabel: 'Хоразм',
        districtLabel: 'Гурлан',
      );
      await tester.pumpWidget(app(const BrandTitleColumn()));
      await tester.pumpAndSettle();
      expect(find.text('Гурлен'), findsOneWidget);
      expect(find.text('Гурлан'), findsNothing);
      // Сақланадиган ёрлиқ ўзгармади.
      expect(ServiceConfigHolder.districtLabel, 'Гурлан');
      expect(GeoContext.home.districtLabel, 'Гурлан');
    });

    testWidgets('GeoDistrictText: TV клип ёрлиғи «Сирғали» → «Сергели»', (tester) async {
      await tester.pumpWidget(app(const GeoDistrictText('sirgali', fallback: 'Сирғали')));
      expect(find.text('Сирғали'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Сергели'), findsOneWidget);
    });
  });
}

const _gurlan = GeoDistrict(
  id: 'gurlan',
  regionId: 'xorazm',
  name: 'Gurlan tumani',
  nameUz: 'Гурлан тумани',
  nameRu: 'Гурленский район',
  nameRuShort: 'Гурлен',
);

const _regions = [
  GeoRegion(id: 'xorazm', name: 'Xorazm', nameUz: 'Хоразм', nameRu: 'Хорезмская область', nameRuShort: 'Хорезм'),
  GeoRegion(id: 'toshkent_shahri', name: 'Toshkent shahri', nameUz: 'Тошкент шаҳри', nameRu: 'город Ташкент'),
  GeoRegion(id: 'andijon', name: 'Andijon viloyati', nameUz: 'Андижон вилояти', nameRu: 'Андижанская область'),
];

class _FakeRepo implements ServiceConfigRepository {
  int districtCalls = 0;

  static const _districts = {
    'gurlan': _gurlan,
    'sirgali': GeoDistrict(
      id: 'sirgali',
      regionId: 'toshkent_shahri',
      name: 'Sirgʻali tumani',
      nameUz: 'Сирғали тумани',
      nameRu: 'Сергелийский район',
      nameRuShort: 'Сергели',
    ),
    'urganch_shahri': GeoDistrict(
      id: 'urganch_shahri',
      regionId: 'xorazm',
      name: 'Urganch shahri',
      nameUz: 'Урганч шаҳри',
      nameRu: 'город Ургенч',
    ),
    // Эски ҳужжат — русча ном йўқ.
    'old': GeoDistrict(id: 'old', regionId: 'xorazm', name: 'Eski tumani', nameUz: 'Эски тумани'),
  };

  @override
  Future<GeoDistrict?> fetchDistrict(String districtId) async {
    districtCalls++;
    return _districts[districtId];
  }

  @override
  Future<GeoRegion?> fetchRegion(String regionId) async =>
      _regions.where((r) => r.id == regionId).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
