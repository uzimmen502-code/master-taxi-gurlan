import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/geo_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ҳудуд тугмаси ойнаси (D-GEO-1/12): фаол ҳудудни ўзгартиради, профилни
/// эмас; яшаш жойи — алоҳида ҳавола.
void main() {
  const gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan', regionLabel: 'Хоразм', districtLabel: 'Гурлан');
  const chilonzor = GeoArea(
      regionId: 'toshkent_shahri', districtId: 'chilonzor', regionLabel: 'Тошкент', districtLabel: 'Чилонзор');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeoContext.resetForTest();
    GeoContext.homeOverride = () => gurlan;
  });

  Future<int> open(WidgetTester tester, {GeoArea? current}) async {
    var homeChanges = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showGeoSelectorSheet(ctx, current: current, onChangeHome: () async => homeChanges++),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return homeChanges;
  }

  testWidgets('локация бор — «Ҳозирги жойим» танланса фаол ҳудуд ўтади, профил эмас', (tester) async {
    await open(tester, current: chilonzor);
    expect(find.text('Чилонзор, Тошкент'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('geo_opt_current')));
    await tester.pumpAndSettle();
    expect(GeoContext.active, chilonzor);
    expect(GeoContext.activeSource, GeoAreaSource.location);
    expect(GeoContext.home, gurlan);
  });

  testWidgets('локация йўқ — «Ҳозирги жойим» пункти кўринмайди', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('geo_opt_current')), findsNothing);
    expect(find.byKey(const ValueKey('geo_opt_home')), findsOneWidget);
  });

  testWidgets('«Яшаш жойим» — яна яшаш жойига эргашади', (tester) async {
    await GeoContext.setActive(chilonzor, GeoAreaSource.manual);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('geo_opt_home')));
    await tester.pumpAndSettle();
    expect(GeoContext.isAway, isFalse);
  });

  testWidgets('«Яшаш жойимни ўзгартириш» — алоҳида йўл чақирилади', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showGeoSelectorSheet(ctx, onChangeHome: () async => calls++),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('geo_change_home')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(GeoContext.isAway, isFalse);
  });
}
