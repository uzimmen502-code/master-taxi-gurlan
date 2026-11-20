import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/features/home/widgets/home_business_section.dart';
import 'package:ava_gurlan/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// «Яқиндаги бизнеслар»: телефонда харита ОЧИҚ (~180 dp, устида матн йўқ), яқиндаги объектлар белгилари,
/// матн/тугмалар харита ТАГИДА (эга 2026-11-20); вебда — аввалги харитасиз карта.
BusinessPin _pin(String id) => BusinessPin(
      source: BusinessSource.business,
      id: id,
      name: 'Biz $id',
      category: BusinessCategory.values.first,
      lat: 41.84,
      lng: 60.39,
    );

class _Calls {
  final pinsRequests = <(LatLng, bool)>[];
}

Future<(List<String>, _Calls)> _pump(
  WidgetTester t, {
  bool showMap = true,
  LocationCoords? gps,
  bool gpsThrows = false,
  int pinCount = 3,
  bool pinsThrow = false,
}) async {
  final opened = <String>[];
  final calls = _Calls();
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
          loadPins: (center, {required gps}) async {
            calls.pinsRequests.add((center, gps));
            if (pinsThrow) throw StateError('offline');
            return [for (var i = 0; i < pinCount; i++) _pin('b$i')];
          },
          mapBuilder: (center, zoom, pins) =>
              Text('MAP ${center.latitude},${center.longitude} z$zoom n${pins.length}'),
        ),
      ]),
    ),
  ));
  await t.pumpAndSettle();
  return (opened, calls);
}

void main() {
  testWidgets('телефон, GPS бор — марказ фойдаланувчи жойи (zoom 14), белгилар, БИТТА сўров (gps)', (t) async {
    final (_, calls) = await _pump(t, gps: const LocationCoords(lat: 41.84, lng: 60.39));
    expect(find.text('MAP 41.84,60.39 z14.0 n3'), findsOneWidget);
    expect(calls.pinsRequests, hasLength(1));
    expect(calls.pinsRequests.single.$2, isTrue);
  });

  testWidgets('харита 180 dp, устида матн йўқ; матн ва тугмалар харита ТАГИДА', (t) async {
    await _pump(t, gps: const LocationCoords(lat: 41.84, lng: 60.39));
    final map = t.getRect(find.byKey(const ValueKey('home_business_map_card')));
    expect(map.height, HomeBusinessSection.mapHeight);
    expect(HomeBusinessSection.mapHeight, 180);
    for (final label in ['bizmap_open_map', 'bizmap_add_mine', 'bizmap_home_sub']) {
      expect(t.getRect(find.text(label)).top, greaterThanOrEqualTo(map.bottom), reason: label);
    }
  });

  testWidgets('белгилар чеклови 20 та', (t) async {
    await _pump(t, gps: const LocationCoords(lat: 41.84, lng: 60.39), pinCount: 35);
    expect(HomeBusinessSection.markerLimit, 20);
    expect(find.text('MAP 41.84,60.39 z14.0 n20'), findsOneWidget);
  });

  testWidgets('рухсат/GPS йўқ ёки хато — бутун мамлакат (бизнес харитаси билан бир хил), сўров gps=false', (t) async {
    final (_, calls) = await _pump(t);
    expect(find.text('MAP 41.3,64.6 z5.6 n3'), findsOneWidget);
    expect(calls.pinsRequests.single.$2, isFalse);
    await _pump(t, gpsThrows: true);
    expect(find.text('MAP 41.3,64.6 z5.6 n3'), findsOneWidget);
  });

  testWidgets('белгилар юкланмаса — харита белгисиз қолади, crash йўқ', (t) async {
    await _pump(t, gps: const LocationCoords(lat: 41.84, lng: 60.39), pinsThrow: true);
    expect(find.text('MAP 41.84,60.39 z14.0 n0'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('вебда харита йўқ — аввалги оқ карта, жойлашув ва сўров йўқ', (t) async {
    var asked = false;
    var loaded = false;
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
          loadPins: (_, {required gps}) async {
            loaded = true;
            return const [];
          },
          mapBuilder: (c, z, p) => const Text('MAP'),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('MAP'), findsNothing);
    expect(find.byKey(const ValueKey('home_business_map_card')), findsNothing);
    expect(asked, isFalse);
    expect(loaded, isFalse);
    expect(find.text('bizmap_open_map'), findsOneWidget);
  });

  testWidgets('харита босилса — тўлиқ бизнес харитаси; «қўшиш» — ўз объектлари', (t) async {
    final (opened, _) = await _pump(t);
    await t.tap(find.byKey(const ValueKey('home_business_map_card')));
    await t.tap(find.text('bizmap_add_mine'));
    expect(opened, ['map', 'add']);
  });
}
