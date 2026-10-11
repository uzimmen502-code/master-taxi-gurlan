import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/geo_tier_bar.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan', regionLabel: 'Хоразм', districtLabel: 'Гурлан');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeoContext.resetForTest();
    GeoContext.homeOverride = () => gurlan;
  });

  testWidgets('тугмалар: туман/вилоят номи, танлов сақланади', (tester) async {
    GeoScope? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GeoTierBar(
          moduleId: 'cheap_products_home',
          scope: GeoContext.scopeFor('cheap_products_home'),
          onChanged: (s) => got = s,
        ),
      ),
    ));
    expect(find.text('Гурлан'), findsOneWidget);
    expect(find.text('Хоразм'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('geo_tier_region')));
    await tester.pumpAndSettle();
    expect(got?.level, GeoLevel.region);
    expect(GeoContext.scopeFor('cheap_products_home').level, GeoLevel.region);
  });

  testWidgets('Туман ичида юк — фақат туман ва вилоят (Республика йўқ, D-GEO-6)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GeoTierBar(moduleId: 'yuk_local', scope: GeoContext.scopeFor('yuk_local'), onChanged: (_) {}),
      ),
    ));
    expect(find.byKey(const ValueKey('geo_tier_nation')), findsNothing);
    expect(find.byKey(const ValueKey('geo_tier_region')), findsOneWidget);
  });

  testWidgets('Хитой — битта даража, тугмалар йўқ', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GeoTierBar(moduleId: 'china_market', scope: GeoContext.scopeFor('china_market'), onChanged: (_) {}),
      ),
    ));
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('кенгроқ таклиф: туманда — вилоят ва Республика; Республикада — йўқ', (tester) async {
    GeoScope? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GeoWiderHint(
          moduleId: 'jobs',
          scope: const GeoScope(level: GeoLevel.district, area: gurlan),
          onChanged: (s) => got = s,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('geo_wider_region')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('geo_wider_nation')));
    await tester.pumpAndSettle();
    expect(got?.level, GeoLevel.nation);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GeoWiderHint(
          moduleId: 'jobs',
          scope: const GeoScope(level: GeoLevel.nation, area: gurlan),
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('geo_wider_region')), findsNothing);
  });
}
