import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/home_business_section.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Яқиндаги бизнеслар»: оқ фон ўрнига харита (эга, 2026-10-26; танлов — «фақат телефонда»).
Future<List<String>> _pump(WidgetTester t, {bool showMap = true, LocationCoords? gps, bool gpsThrows = false}) async {
  final opened = <String>[];
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ListView(children: [
        HomeBusinessSection(
          onOpenMap: () => opened.add('map'),
          onAddMine: () => opened.add('add'),
          showMap: showMap,
          locate: () async {
            if (gpsThrows) throw StateError('gps');
            return gps;
          },
          mapBuilder: (center, zoom) => Text('MAP ${center.latitude},${center.longitude} z$zoom'),
        ),
      ]),
    ),
  ));
  await t.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('телефон, GPS рухсати бор — марказ фойдаланувчи жойи (zoom 14)', (t) async {
    await _pump(t, gps: const LocationCoords(lat: 41.84, lng: 60.39));
    expect(find.text('MAP 41.84,60.39 z14.0'), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('home_business_map_card'))).height, HomeBusinessSection.mapHeight);
    expect(find.text('bizmap_open_map'), findsOneWidget, reason: 'тугмалар харита устида қолади');
  });

  testWidgets('рухсат/GPS йўқ ёки хато — бутун мамлакат (бизнес харитаси билан бир хил)', (t) async {
    await _pump(t);
    expect(find.text('MAP 41.3,64.6 z5.6'), findsOneWidget);
    await _pump(t, gpsThrows: true);
    expect(find.text('MAP 41.3,64.6 z5.6'), findsOneWidget);
  });

  testWidgets('вебда харита йўқ — аввалги оқ карта, жойлашув сўралмайди', (t) async {
    var asked = false;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: HomeBusinessSection(
          onOpenMap: () {},
          onAddMine: () {},
          showMap: false,
          locate: () async {
            asked = true;
            return null;
          },
          mapBuilder: (c, z) => const Text('MAP'),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('MAP'), findsNothing);
    expect(find.byKey(const ValueKey('home_business_map_card')), findsNothing);
    expect(asked, isFalse);
  });

  testWidgets('харита устига босиш — тўлиқ бизнес харитаси; «қўшиш» — ўз объектлари', (t) async {
    final opened = await _pump(t);
    await t.tap(find.textContaining('MAP '));
    await t.tap(find.text('bizmap_add_mine'));
    expect(opened, ['map', 'add']);
  });
}
