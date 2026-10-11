import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Geo пойдевори (D-GEO-1/10/12/15): яшаш / фаол / модул танлови.
void main() {
  const gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan', regionLabel: 'Хоразм', districtLabel: 'Гурлан');
  const chilonzor = GeoArea(
      regionId: 'toshkent_shahri', districtId: 'chilonzor', regionLabel: 'Тошкент', districtLabel: 'Чилонзор');
  var home = gurlan;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeoContext.resetForTest();
    home = gurlan;
    GeoContext.homeOverride = () => home;
  });

  group('фаол ҳудуд', () {
    test('танланмаган — яшаш жойига эргашади', () {
      expect(GeoContext.active, gurlan);
      expect(GeoContext.activeSource, GeoAreaSource.home);
      home = chilonzor; // профил ўзгарди
      expect(GeoContext.active, chilonzor);
    });

    test('бошқа ҳудуд танланса — профил (home) ўзгармайди', () async {
      await GeoContext.setActive(chilonzor, GeoAreaSource.location);
      expect(GeoContext.active, chilonzor);
      expect(GeoContext.home, gurlan);
      expect(GeoContext.isAway, isTrue);
      expect(GeoContext.activeSource, GeoAreaSource.location);
    });

    test('яшаш жойи танланса — эргашиш режимига қайтади', () async {
      await GeoContext.setActive(chilonzor, GeoAreaSource.manual);
      await GeoContext.setActive(gurlan, GeoAreaSource.manual);
      expect(GeoContext.isAway, isFalse);
      expect(GeoContext.activeSource, GeoAreaSource.home);
    });

    test('сақланади ва қайта юкланади', () async {
      await GeoContext.setActive(chilonzor, GeoAreaSource.manual);
      GeoContext.resetForTest();
      GeoContext.homeOverride = () => gurlan;
      await GeoContext.load();
      expect(GeoContext.active, chilonzor);
      expect(GeoContext.activeSource, GeoAreaSource.manual);
    });

    test('revision ҳар ўзгаришда ошади', () async {
      final before = GeoContext.revision.value;
      await GeoContext.setActive(chilonzor, GeoAreaSource.manual);
      expect(GeoContext.revision.value, greaterThan(before));
    });
  });

  group('модул танлови', () {
    test('сукут — қоидадаги даража + фаол ҳудуд', () {
      final s = GeoContext.scopeFor('cheap_products_home');
      expect(s.level, GeoLevel.district);
      expect(s.area, gurlan);
      expect(s.districtFilter, 'gurlan');
      expect(s.regionFilter, '');
    });

    test('даража сақланади, ҳудуд фаол ҳудудга эргашади (pinned эмас)', () async {
      await GeoContext.setScope('cheap_products_home', const GeoScope(level: GeoLevel.region, area: gurlan));
      await GeoContext.setActive(chilonzor, GeoAreaSource.location);
      final s = GeoContext.scopeFor('cheap_products_home');
      expect(s.level, GeoLevel.region);
      expect(s.area, chilonzor);
      expect(s.regionFilter, 'toshkent_shahri');
    });

    test('модулда атайлаб танланган ҳудуд (pinned) — сақланади (Кўчмас мулк, D-GEO-15)', () async {
      await GeoContext.setScope('realty', const GeoScope(level: GeoLevel.district, area: chilonzor, pinned: true));
      await GeoContext.setActive(gurlan, GeoAreaSource.manual);
      GeoContext.resetForTest();
      GeoContext.homeOverride = () => gurlan;
      await GeoContext.load();
      expect(GeoContext.scopeFor('realty').area, chilonzor);
    });

    test('Улгуржи: ҳар сафар «Бутун Ўзбекистон», танлов сақланмайди (D-GEO-10)', () async {
      expect(GeoContext.scopeFor('wholesale_market').level, GeoLevel.nation);
      await GeoContext.setScope('wholesale_market', const GeoScope(level: GeoLevel.region, area: gurlan));
      expect(GeoContext.scopeFor('wholesale_market').level, GeoLevel.region); // экран очиқ
      GeoContext.clearSessionScope('wholesale_market'); // экран ёпилди
      expect(GeoContext.scopeFor('wholesale_market').level, GeoLevel.nation);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('wholesale')), isEmpty);
    });

    test('рухсат этилмаган даража ёзилмайди (Хитой — фақат Республика)', () async {
      await GeoContext.setScope('china_market', const GeoScope(level: GeoLevel.district, area: gurlan));
      expect(GeoContext.scopeFor('china_market').level, GeoLevel.nation);
    });

    test('Республика даражасида фильтр йўқ', () {
      const s = GeoScope(level: GeoLevel.nation, area: gurlan);
      expect(s.districtFilter, '');
      expect(s.regionFilter, '');
    });
  });

  group('ModuleGeoPolicy жадвали', () {
    test('эга қарорлари', () {
      expect(geoPolicyFor('china_market').mode, GeoMode.nationwide);
      expect(geoPolicyFor('wholesale_market').persistSelection, isFalse);
      expect(geoPolicyFor('wholesale_market').defaultLevel, GeoLevel.nation);
      expect(geoPolicyFor('yuk_local').levels, [GeoLevel.district, GeoLevel.region]);
      expect(geoPolicyFor('courier').mode, GeoMode.distance);
      expect(geoPolicyFor('restaurants').mode, GeoMode.distance);
      expect(geoPolicyFor('dating').mode, GeoMode.none);
      expect(geoPolicyFor('realty').persistSelection, isTrue);
      expect(geoPolicyFor('intercity').mode, GeoMode.route);
    });

    test('жадвалда йўқ модул — ҳудудсиз', () {
      expect(geoPolicyFor('umuman_yoq').mode, GeoMode.none);
    });

    test('ҳар қоидада сукут даража рухсат этилган даражалар ичида', () {
      for (final p in kModuleGeoPolicies.values) {
        if (p.levels.isEmpty) continue;
        expect(p.levels.contains(p.defaultLevel), isTrue, reason: p.moduleId);
      }
    });
  });
}
