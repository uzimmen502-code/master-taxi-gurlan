import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_station_sheet.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Xaritadagi stansiya markeri bosilganda ochiladigan varaq va tanlov holati.
// `AppLocalizations` ulanmagan: `context.tr(key)` kalitning o'zini qaytaradi.
// Xarita `mapBuilder` bilan soxta: marker bosilishi `onStationTap` orqali
// beriladi (haqiqiy GoogleMap platforma ko'rinishi kerak emas).

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

EvChargingStation _station(String id, double along,
        {String? name, bool imported = false}) =>
    EvChargingStation(
      id: id,
      latitude: _lat(along),
      longitude: 60.0,
      geohash: '',
      chargingTypes: const ['DC', 'AC'],
      connectors: const ['CCS2', 'Type 2'],
      powerKw: 120,
      status: imported ? 'unknown' : 'working',
      verificationStatus: imported ? 'unverified' : 'verified',
      confirmationCount: imported ? 0 : 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: name ?? 'ST-$id',
      sourceType: imported ? 'import' : null,
      sourceProvider: imported ? 'osm' : null,
    );

EvTripStop _stop(String id, double along, [List<EvTripBackup> b = const []]) =>
    EvTripStop(
      station: _station(id, along),
      alongKm: along,
      offRouteKm: 0,
      legKm: along,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: b,
    );

EvTripBackup _backup(String id, double stopAlong, double delta) => EvTripBackup(
      station: _station(id, stopAlong + delta),
      alongKm: stopAlong + delta,
      offRouteKm: 2.4,
      deltaKm: delta,
    );

EvTripPlan _plan() => EvTripPlan(
      status: EvTripPlanStatus.ok,
      stops: [
        _stop('p1', 200, [_backup('b1', 200, 30)]),
        _stop('p2', 400),
      ],
      totalKm: 640,
      arrivalSocPercent: 25,
    );

/// Yo'l bo'yidagi stansiyalar: tavsiya etilgan 2 ta, zaxira 1 ta va boshqa 12 ta.
List<EvCorridorStation> _corridor() => [
      for (var i = 0; i < 12; i++)
        EvCorridorStation(
            station: _station('x$i', 20.0 + i * 45), alongKm: 20.0 + i * 45, offRouteKm: 3.6),
      EvCorridorStation(station: _station('p1', 200), alongKm: 200, offRouteKm: 0),
      EvCorridorStation(station: _station('b1', 230), alongKm: 230, offRouteKm: 2.4),
      EvCorridorStation(station: _station('p2', 400), alongKm: 400, offRouteKm: 0),
    ];

class _Source implements EvCarLocationSource {
  final ctrl = StreamController<EvCarFix>.broadcast();
  @override
  Future<Stream<EvCarFix>?> open() async => ctrl.stream;
}

class _H {
  EvTripMapRenderData? last;
  final calls = <List<EvWaypoint>>[];
}

const _toggle = ValueKey('ev_station_sheet_toggle');
const _label = ValueKey('ev_trip_navigate_label');

Future<_H> _pumpScreen(
  WidgetTester tester, {
  int? maxWaypoints,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final h = _H();
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EvTripMapScreen(
                  plan: _plan(),
                  route: [
                    for (var i = 0; i <= 100; i += 10)
                      EvRoutePoint(_lat(i * 6.4), 60.0)
                  ],
                  corridorStations: _corridor(),
                  originLat: _lat(0),
                  originLng: 60.0,
                  destinationLat: _lat(640),
                  destinationLng: 60.0,
                  onOpenNavigator: () {},
                  locationSource: _Source(),
                  maxWaypoints: maxWaypoints,
                  routeLauncher: ({
                    required double originLat,
                    required double originLng,
                    required double destinationLat,
                    required double destinationLng,
                    List<EvWaypoint> stops = const [],
                  }) async {
                    h.calls.add(stops);
                    return true;
                  },
                  mapBuilder: (context, data) {
                    h.last = data;
                    return const ColoredBox(
                      color: Color(0xFFCCDDEE),
                      child: SizedBox.expand(),
                    );
                  },
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _tapToggle(WidgetTester tester) async {
  await tester.tap(find.byKey(_toggle));
  await tester.pumpAndSettle();
}

Future<void> _pumpSheet(
  WidgetTester tester,
  EvTripCandidate c, {
  int? number,
  bool canAdd = true,
  int max = 9,
  double textScale = 1.0,
  VoidCallback? onToggle,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: EvTripStationSheet(
        candidate: c,
        number: number,
        canAdd: canAdd,
        maxWaypoints: max,
        onToggle: onToggle ?? () {},
      ),
    ),
  ));
}

EvTripCandidate _cand(EvTripMarkerKind kind,
        {double along = 123.4, double off = 2.4, EvChargingStation? st}) =>
    EvTripCandidate(
      station: st ?? _station('c1', along),
      alongKm: along,
      offRouteKm: off,
      kind: kind,
    );

void main() {
  group('xarita: yo\'l bo\'yidagi BARCHA stansiyalar xaritaga beriladi', () {
    testWidgets('koridordagi 15 ta stansiyaning hammasi (kamaytirilmaydi)',
        (tester) async {
      final h = await _pumpScreen(tester);
      expect(h.last!.candidates, hasLength(15));
      expect({for (final c in h.last!.candidates) c.id}.length, 15);
      // Tavsiya / zaxira / boshqa turlari.
      final kinds = {for (final c in h.last!.candidates) c.id: c.kind};
      expect(kinds['p1'], EvTripMarkerKind.primary);
      expect(kinds['b1'], EvTripMarkerKind.backup);
      expect(kinds['x0'], EvTripMarkerKind.other);
      // Boshlang'ich tanlov: tavsiya etilganlar, raqamlar yo'l bo'yicha.
      expect(h.last!.selectedNumbers, {'p1': 1, 'p2': 2});
    });
  });

  group('marker bosildi -> varaq', () {
    testWidgets('tavsiya etilgan: "Tavsiya" belgisi, nom, masofalar, '
        '"Rejadan olib tashlash"', (tester) async {
      final h = await _pumpScreen(tester);
      h.last!.onStationTap('p1');
      await tester.pumpAndSettle();

      expect(find.byType(EvTripStationSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_station_badge_recommended')),
          findsOneWidget);
      expect(find.text('ev_trip_badge_recommended'), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_station_badge_backup')), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('ev_station_sheet_title')))
              .data,
          'ST-p1');
      expect(find.text('ev_trip_from_start: 200 ev_trip_km'), findsOneWidget);
      expect(find.text('ev_trip_on_route'), findsOneWidget);
      expect(find.text('ev_trip_remove_stop'), findsOneWidget);
      expect(find.text('ev_trip_add_stop'), findsNothing);
      // Tanlangan: raqam (1) ko'rinadi.
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey('ev_station_sheet_number')),
                  matching: find.byType(Text)))
              .data,
          '1');
    });

    testWidgets('zaxira: "Zaxira" belgisi, yo\'ldan N km, qo\'shish tugmasi',
        (tester) async {
      final h = await _pumpScreen(tester);
      h.last!.onStationTap('b1');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ev_station_badge_backup')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('ev_station_badge_backup')),
              matching: find.text('ev_trip_legend_backup')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('ev_station_badge_recommended')),
          findsNothing);
      expect(find.text('ev_trip_add_stop'), findsOneWidget);
      expect(find.text('ev_trip_off_route 2 ev_trip_km'), findsOneWidget);
      expect(find.text('ev_trip_from_start: 230 ev_trip_km'), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_station_sheet_number')),
          findsNothing);
    });

    testWidgets('boshqa stansiya: belgi YO\'Q, tugma "qo\'shish"',
        (tester) async {
      final h = await _pumpScreen(tester);
      h.last!.onStationTap('x3');
      await tester.pumpAndSettle();

      expect(find.byType(EvTripStationSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_station_badge_recommended')),
          findsNothing);
      expect(find.byKey(const ValueKey('ev_station_badge_backup')), findsNothing);
      expect(find.text('ev_trip_badge_recommended'), findsNothing);
      expect(find.text('ev_trip_add_stop'), findsOneWidget);
      // Yo'ldan 3.6 km -> 4 km (yaxlitlanadi).
      expect(find.text('ev_trip_off_route 4 ev_trip_km'), findsOneWidget);
    });

    testWidgets('noma\'lum id: varaq ochilmaydi, xato yo\'q', (tester) async {
      final h = await _pumpScreen(tester);
      h.last!.onStationTap('nope');
      await tester.pumpAndSettle();
      expect(find.byType(EvTripStationSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('tugma: tanlovni almashtiradi', () {
    testWidgets('boshqa stansiyani qo\'shish: tugmada soni 3, raqamlar yo\'l '
        'bo\'yicha qayta tartiblanadi, varaq yopiladi', (tester) async {
      final h = await _pumpScreen(tester);
      expect(tester.widget<Text>(find.byKey(_label)).data,
          'ev_trip_navigate · 2');

      h.last!.onStationTap('x2'); // 110 km - p1 (200) dan oldin
      await tester.pumpAndSettle();
      await _tapToggle(tester);

      expect(find.byType(EvTripStationSheet), findsNothing);
      expect(tester.widget<Text>(find.byKey(_label)).data,
          'ev_trip_navigate · 3');
      expect(h.last!.selectedNumbers, {'x2': 1, 'p1': 2, 'p2': 3});

      // Qayta bosilsa - "olib tashlash".
      h.last!.onStationTap('x2');
      await tester.pumpAndSettle();
      expect(find.text('ev_trip_remove_stop'), findsOneWidget);
      await _tapToggle(tester);
      expect(h.last!.selectedNumbers, {'p1': 1, 'p2': 2});
      expect(tester.widget<Text>(find.byKey(_label)).data,
          'ev_trip_navigate · 2');
    });

    testWidgets('tavsiya etilganni olib tashlash mumkin; hammasi bo\'sh '
        'bo\'lsa tugma faqat "Navigatsiya"', (tester) async {
      final h = await _pumpScreen(tester);
      for (final id in ['p1', 'p2']) {
        h.last!.onStationTap(id);
        await tester.pumpAndSettle();
        await _tapToggle(tester);
      }
      expect(h.last!.selectedNumbers, isEmpty);
      expect(tester.widget<Text>(find.byKey(_label)).data, 'ev_trip_navigate');
    });

    testWidgets('chegara (3): 3 ta bo\'lganda yangi qo\'shib bo\'lmaydi - tugma '
        'o\'chiq, sababi yozilgan; mavjudini olib tashlash mumkin',
        (tester) async {
      final h = await _pumpScreen(tester, maxWaypoints: 3);
      h.last!.onStationTap('b1');
      await tester.pumpAndSettle();
      await _tapToggle(tester); // 3/3
      expect(h.last!.selectedNumbers.length, 3);

      h.last!.onStationTap('x5');
      await tester.pumpAndSettle();
      final btn = tester.widget<ElevatedButton>(find.byKey(_toggle));
      expect(btn.onPressed, isNull, reason: 'qo\'shib bo\'lmaydi');
      expect(find.byKey(const ValueKey('ev_station_sheet_limit')),
          findsOneWidget);
      expect(find.text('ev_trip_sel_full'), findsOneWidget);
      // O'chiq tugma kulrang.
      final bg = btn.style!.backgroundColor!.resolve({WidgetState.disabled});
      expect(bg, const Color(0xFFBDBDBD));
      await tester.tapAt(const Offset(200, 20)); // to'siq - yopish
      await tester.pumpAndSettle();
      expect(h.last!.selectedNumbers.length, 3, reason: 'o\'zgarmadi');

      // Tanlanganni olib tashlash hamon mumkin.
      h.last!.onStationTap('b1');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(find.byKey(_toggle)).onPressed,
          isNotNull);
      expect(find.byKey(const ValueKey('ev_station_sheet_limit')),
          findsNothing);
      await _tapToggle(tester);
      expect(h.last!.selectedNumbers.length, 2);
    });

    testWidgets('tanlangan tartib bilan Google Maps ochiladi', (tester) async {
      final h = await _pumpScreen(tester);
      h.last!.onStationTap('x2'); // 110
      await tester.pumpAndSettle();
      await _tapToggle(tester);
      h.last!.onStationTap('p1'); // olib tashlash
      await tester.pumpAndSettle();
      await _tapToggle(tester);

      await tester.tap(find.byKey(const ValueKey('ev_trip_navigate_button')));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(h.calls.single.map((w) => w.lat).toList(),
          [_lat(20.0 + 2 * 45), _lat(400)]);
    });
  });

  group('varaq ko\'rinishi (alohida)', () {
    testWidgets('tugma brend rangida (primaryDark / onPrimary), katta',
        (tester) async {
      await _pumpSheet(tester, _cand(EvTripMarkerKind.other));
      final btn = tester.widget<ElevatedButton>(find.byKey(_toggle));
      expect(btn.style!.backgroundColor!.resolve({}), AppColors.primaryDark);
      expect(btn.style!.foregroundColor!.resolve({}), AppColors.onPrimary);
      expect(tester.getSize(find.byKey(_toggle)).height,
          greaterThanOrEqualTo(56));
      expect(find.text('ev_trip_add_stop'), findsOneWidget);
    });

    testWidgets('nomsiz stansiya: umumiy nom; tekshirilmagan import belgisi',
        (tester) async {
      final st = EvChargingStation(
        id: 'u1',
        latitude: _lat(10),
        longitude: 60.0,
        geohash: '',
        chargingTypes: const ['DC'],
        connectors: const [],
        powerKw: null,
        status: 'unknown',
        verificationStatus: 'unverified',
        confirmationCount: 0,
        reportCount: 0,
        createdBy: 'import',
        isActive: true,
        sourceType: 'import',
        sourceProvider: 'osm',
      );
      await _pumpSheet(tester, _cand(EvTripMarkerKind.other, st: st));
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('ev_station_sheet_title')))
              .data,
          'ev_trip_station');
      expect(find.text('ev_trip_unverified'), findsOneWidget);
    });

    testWidgets('yo\'l ustida (<1 km) - "Yo\'l ustida"; zaryadlash turi, kW, '
        'razyomlar', (tester) async {
      await _pumpSheet(tester, _cand(EvTripMarkerKind.other, off: 0.4));
      expect(find.text('ev_trip_on_route'), findsOneWidget);
      expect(find.textContaining('ev_trip_off_route'), findsNothing);
      expect(find.text('DC+AC · 120 kW · CCS2 · Type 2'), findsOneWidget);
    });

    testWidgets('onToggle chaqiriladi', (tester) async {
      var n = 0;
      await _pumpSheet(tester, _cand(EvTripMarkerKind.backup),
          onToggle: () => n++);
      await tester.tap(find.byKey(_toggle));
      expect(n, 1);
    });

    testWidgets('katta shrift (1.3): matnlar kesilmaydi, overflow yo\'q',
        (tester) async {
      await _pumpSheet(
        tester,
        _cand(EvTripMarkerKind.primary,
            st: _station('long', 200,
                name: 'Juda uzun nomli zaryadlash stansiyasi — Buxoro viloyati, Qorovulbozor tumani')),
        number: 3,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.byKey(const ValueKey('ev_station_sheet_title')));
      expect(title.overflow, isNot(TextOverflow.ellipsis));
      expect(title.maxLines, isNull);
      expect(find.text('ev_trip_remove_stop'), findsOneWidget);
    });
  });

  group('katta shrift (1.3) ekranda', () {
    testWidgets('"Navigatsiya · 9" tugmasi ekranga sig\'adi, xatosiz',
        (tester) async {
      final h = await _pumpScreen(tester, textScale: 1.3);
      for (final id in ['x0', 'x1', 'x2', 'x3', 'x4', 'x5', 'x6']) {
        h.last!.onStationTap(id);
        await tester.pumpAndSettle();
        await _tapToggle(tester);
      }
      expect(tester.widget<Text>(find.byKey(_label)).data,
          'ev_trip_navigate · 9');
      expect(tester.takeException(), isNull);
      final r = tester.getRect(find.byKey(const ValueKey('ev_trip_navigate_button')));
      expect(r.right, lessThanOrEqualTo(400));
      expect(r.bottom, lessThanOrEqualTo(800));
    });

    testWidgets('yig\'iq varaqada sarlavha kesilmaydi (2 qatorgacha)',
        (tester) async {
      await _pumpScreen(tester, textScale: 1.3);
      final peek = tester.widget<Text>(find.byKey(const ValueKey('ev_trip_sheet_peek')));
      expect(peek.maxLines, 2);
      expect(peek.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });
  });
}
