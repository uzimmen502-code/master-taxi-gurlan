import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_map_top_overlay.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_station_sheet.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Xaritadagi katta "Navigatsiya" tugmasi: joylashuvi (varaqa yopiq / ochiq /
// sudralayotganda), bosilganda chaqiriladigan funksiya (asl koordinata va
// oraliq nuqtalar = haydovchi tanlagan stansiyalar), chegaradan oshish xabari,
// o'chiq holat va xatolar.
// `AppLocalizations` ulanmagan: `context.tr(key)` kalitning o'zini qaytaradi.
// Xarita `mapBuilder` bilan soxta, GPS - soxta oqim.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

EvChargingStation _station(String id, double along) => EvChargingStation(
      id: id,
      latitude: _lat(along),
      longitude: 60.0,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: 120,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: 'ST-$id',
    );

EvTripBackup _backup(String id, double stopAlong, double delta) => EvTripBackup(
      station: _station(id, stopAlong + delta),
      alongKm: stopAlong + delta,
      offRouteKm: 1,
      deltaKm: delta,
    );

EvTripStop _stop(String id, double along,
        [List<EvTripBackup> backups = const []]) =>
    EvTripStop(
      station: _station(id, along),
      alongKm: along,
      offRouteKm: 0,
      legKm: along,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: backups,
    );

EvTripPlan _planNoBackups() => EvTripPlan(
      status: EvTripPlanStatus.ok,
      stops: [_stop('s1', 200), _stop('s2', 400)],
      totalKm: 640,
      arrivalSocPercent: 25,
    );

EvTripPlan _planWithBackups({
  EvTripPlanStatus status = EvTripPlanStatus.ok,
}) =>
    EvTripPlan(
      status: status,
      stops: [
        _stop('s1', 200, [_backup('b1-', 200, -30), _backup('b1+', 200, 20)]),
        _stop('s2', 400, [_backup('b2+', 400, 15)]),
      ],
      totalKm: 640,
      arrivalSocPercent: 25,
    );

List<EvRoutePoint> _route() =>
    [for (var i = 0; i <= 100; i += 10) EvRoutePoint(_lat(i * 6.4), 60.0)];

class _Source implements EvCarLocationSource {
  final ctrl = StreamController<EvCarFix>.broadcast();
  @override
  Future<Stream<EvCarFix>?> open() async => ctrl.stream;
}

class _Call {
  _Call(this.originLat, this.originLng, this.destLat, this.destLng, this.stops);
  final double originLat, originLng, destLat, destLng;
  final List<EvWaypoint> stops;
}

class _H {
  final calls = <_Call>[];
  bool result = true;
  bool throwError = false;
  Completer<bool>? hold;
  final source = _Source();
  EvTripMapRenderData? last;
}

const _btn = ValueKey('ev_trip_navigate_button');
const _label = ValueKey('ev_trip_navigate_label');

Future<_H> _pump(
  WidgetTester tester, {
  EvTripPlan? plan,
  List<EvRoutePoint>? route,
  double? destLat,
  int? maxWaypoints,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final h = _H();
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EvTripMapScreen(
                  plan: plan ?? _planNoBackups(),
                  route: route ?? _route(),
                  corridorStations: const [],
                  originLat: _lat(0),
                  originLng: 60.0,
                  destinationLat: destLat ?? _lat(640),
                  destinationLng: 60.0,
                  onOpenNavigator: () {},
                  locationSource: h.source,
                  maxWaypoints: maxWaypoints,
                  routeLauncher: ({
                    required double originLat,
                    required double originLng,
                    required double destinationLat,
                    required double destinationLng,
                    List<EvWaypoint> stops = const [],
                  }) async {
                    h.calls.add(_Call(originLat, originLng, destinationLat,
                        destinationLng, stops));
                    if (h.throwError) throw StateError('launch failed');
                    if (h.hold != null) return h.hold!.future;
                    return h.result;
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

final _header = find.byKey(const ValueKey('ev_trip_sheet_header'));

/// Tugma ekran ichida, to'liq ko'rinadi va bosilsa chaqiruv ketadi.
Future<void> _expectVisibleAndTappable(WidgetTester tester, _H h) async {
  final r = tester.getRect(find.byKey(_btn));
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(r.top, greaterThanOrEqualTo(kToolbarHeight),
      reason: 'AppBar (orqaga) ostiga chiqmaydi: $r');
  expect(r.bottom, lessThanOrEqualTo(screen.height), reason: '$r');
  expect(r.left, greaterThanOrEqualTo(0));
  expect(r.right, lessThanOrEqualTo(screen.width));
  expect(r.height, greaterThanOrEqualTo(56));

  final before = h.calls.length;
  await tester.tap(find.byKey(_btn));
  await tester.pump();
  expect(h.calls.length, before + 1,
      reason: 'tugma varaqa ustida turibdi va bosiladi');
}

void main() {
  group('katta tugma: ko\'rinish', () {
    testWidgets('matn, ikonka, rang, o\'lcham', (tester) async {
      await _pump(tester);
      expect(find.byKey(_btn), findsOneWidget);
      // Tanlangan (tavsiya etilgan) 2 ta to'xtash soni tugmada.
      expect(tester.widget<Text>(find.byKey(_label)).data,
          'ev_trip_navigate · 2');
      expect(
          find.descendant(
              of: find.byKey(_btn),
              matching: find.byIcon(Icons.navigation_rounded)),
          findsOneWidget);

      final m = tester.widget<Material>(find.byKey(_btn));
      expect(m.color, AppColors.primaryDark);
      final text = tester.widget<Text>(find.byKey(_label));
      expect(text.style!.color, AppColors.onPrimary);

      final r = tester.getRect(find.byKey(_btn));
      expect(r.height, greaterThanOrEqualTo(56));
      expect(r.width, greaterThan(300), reason: 'kichkina emas, deyarli to\'liq');
      expect(r.center.dx, closeTo(200, 0.5), reason: 'pastki markazda');
    });

    testWidgets('yopiq varaqa (peek): varaqa tepasida, ko\'rinadi, bosiladi',
        (tester) async {
      final h = await _pump(tester);
      final btn = tester.getRect(find.byKey(_btn));
      final sheetTop = tester.getTopLeft(_header).dy;
      expect(btn.bottom, lessThanOrEqualTo(sheetTop),
          reason: 'varaqa sarlavhasini yopmaydi');
      expect(sheetTop - btn.bottom, lessThan(40), reason: 'varaqaga yopishgan');
      await _expectVisibleAndTappable(tester, h);
    });

    testWidgets('varaqa o\'rtacha ochilganda (0.6) tugma birga ko\'tariladi',
        (tester) async {
      final h = await _pump(tester);
      final y0 = tester.getRect(find.byKey(_btn)).top;
      await tester.tap(_header);
      await tester.pumpAndSettle();
      final btn = tester.getRect(find.byKey(_btn));
      expect(btn.top, lessThan(y0 - 100), reason: 'varaqa bilan ko\'tarildi');
      expect(btn.bottom, lessThanOrEqualTo(tester.getTopLeft(_header).dy));
      await _expectVisibleAndTappable(tester, h);
    });

    testWidgets('varaqa to\'liq ochilganda tugma ekranda qoladi (pastga yopishadi)',
        (tester) async {
      final h = await _pump(tester);
      await tester.drag(_header, const Offset(0, -700));
      await tester.pumpAndSettle();
      // Varaqa deyarli butun ekran: tugma pastga yopishgan, ekranda.
      final btn = tester.getRect(find.byKey(_btn));
      expect(btn.bottom, closeTo(800 - 12, 1));
      await _expectVisibleAndTappable(tester, h);
    });

    testWidgets('varaqa sudralayotganda (qo\'yib yuborilmagan) ham ko\'rinadi',
        (tester) async {
      final h = await _pump(tester);
      final g = await tester.startGesture(tester.getCenter(_header));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, -50));
        await tester.pump();
        final r = tester.getRect(find.byKey(_btn));
        expect(r.top, greaterThanOrEqualTo(kToolbarHeight), reason: 'step $i $r');
        expect(r.bottom, lessThanOrEqualTo(800), reason: 'step $i $r');
      }
      await g.up();
      await tester.pumpAndSettle();
      await _expectVisibleAndTappable(tester, h);
    });

    testWidgets('past ekranda (400x500) ham har holatda ekran ichida',
        (tester) async {
      final h = await _pump(tester, size: const Size(400, 500));
      await _expectVisibleAndTappable(tester, h);
      await tester.drag(_header, const Offset(0, -450));
      await tester.pumpAndSettle();
      final r = tester.getRect(find.byKey(_btn));
      expect(r.bottom, lessThanOrEqualTo(500));
      expect(r.top, greaterThanOrEqualTo(kToolbarHeight));
    });

    testWidgets('"Mening joyim" tugmasi bilan to\'qnashmaydi (tepasida)',
        (tester) async {
      final h = await _pump(tester);
      h.source.ctrl.add(EvCarFix(lat: _lat(10), lng: 60.0));
      await tester.pump();
      await tester.pump();
      final recenter = find.byIcon(Icons.my_location_rounded);
      expect(recenter, findsOneWidget);
      final rr = tester.getRect(recenter);
      final nb = tester.getRect(find.byKey(_btn));
      expect(rr.overlaps(nb), isFalse);
      expect(rr.bottom, lessThanOrEqualTo(nb.top));
      // Orqaga strelkasi bilan ham.
      expect(rr.overlaps(tester.getRect(find.byType(EvMapBackButton))), isFalse);
      expect(nb.overlaps(tester.getRect(find.byType(EvMapBackButton))), isFalse);
    });
  });

  group('bosilganda: Google Maps chaqiruvi (haydovchi tanlovi)', () {
    testWidgets('zaxira yo\'q: darhol; asl koordinatalar + tavsiya etilgan '
        'asosiylar', (tester) async {
      final h = await _pump(tester, plan: _planNoBackups());
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();

      expect(h.calls, hasLength(1));
      final c = h.calls.single;
      expect(c.originLat, closeTo(_lat(0), 1e-12));
      expect(c.originLng, 60.0);
      expect(c.destLat, closeTo(_lat(640), 1e-12));
      expect(c.destLng, 60.0);
      expect(c.stops.map((s) => s.lat).toList(),
          [_lat(200), _lat(400)]);
    });

    testWidgets('zaxira bor: varaqa chiqmaydi, darhol; zaxiralar o\'chiq '
        '(faqat tavsiya etilgan asosiylar)', (tester) async {
      final h = await _pump(tester, plan: _planWithBackups());
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();

      expect(find.byType(EvTripStationSheet), findsNothing);
      expect(h.calls, hasLength(1));
      expect(h.calls.single.stops.map((s) => s.lat).toList(),
          [_lat(200), _lat(400)]);
    });

    testWidgets('haydovchi qo\'shgan/olib tashlagan stansiyalar yo\'l '
        'tartibida jo\'natiladi', (tester) async {
      final h = await _pump(tester, plan: _planWithBackups());
      h.last!.onStationTap('b1-'); // zaxira (170 km)
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      h.last!.onStationTap('b2+'); // zaxira (415 km)
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      h.last!.onStationTap('s1'); // tavsiya etilganni olib tashlash
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(h.calls.single.stops.map((s) => s.lat).toList(), [
        _lat(170), // b1- (qo'shildi)
        _lat(400), // s2
        _lat(415), // b2+ (qo'shildi)
      ]);
    });

    testWidgets('hammasi olib tashlansa: faqat manzilga (oraliq nuqta yo\'q)',
        (tester) async {
      final h = await _pump(tester, plan: _planNoBackups());
      for (final id in ['s1', 's2']) {
        h.last!.onStationTap(id);
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<Text>(find.byKey(_label)).data, 'ev_trip_navigate');
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(h.calls.single.stops, isEmpty);
      expect(h.calls.single.destLat, closeTo(_lat(640), 1e-12));
    });

    testWidgets('tugmada tanlanganlar soni: "Navigatsiya · N", o\'zgarsa '
        'yangilanadi', (tester) async {
      final h = await _pump(tester, plan: _planWithBackups());
      String label() => tester.widget<Text>(find.byKey(_label)).data!;
      expect(label(), 'ev_trip_navigate · 2');

      h.last!.onStationTap('b1+');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      expect(label(), 'ev_trip_navigate · 3');
      expect(h.last!.selectedNumbers.length, 3);

      h.last!.onStationTap('b1+');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      expect(label(), 'ev_trip_navigate · 2');
    });

    testWidgets('aniq chegarada (3/3): xabar yo\'q, Google Maps ochiladi', (tester) async {
      final h =
          await _pump(tester, plan: _planWithBackups(), maxWaypoints: 3);
      // 2 asosiy + 1 zaxira = 3 (chegarada) - hali ruxsat.
      h.last!.onStationTap('b1+');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(find.byKey(const ValueKey('ev_trip_over_limit_message')),
          findsNothing);
    });

    testWidgets('tavsiyalar chegaradan ko\'p (mobil veb 3, 4 asosiy): '
        'bloklanmaydi - birinchi 3 ta yuboriladi, qolgani keyin',
        (tester) async {
      final plan = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [
          _stop('a', 100),
          _stop('b', 200),
          _stop('c', 300),
          _stop('d', 400),
        ],
        totalKm: 640,
        arrivalSocPercent: 25,
      );
      final h = await _pump(tester, plan: plan, maxWaypoints: 3);
      // Tanlov kesilmaydi: tugmada 4.
      expect(tester.widget<Text>(find.byKey(_label)).data,
          'ev_trip_navigate · 4');

      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      // Eski "chegaradan oshdi" bloklovchi xabari yo'q, launcher chaqirildi.
      expect(find.byKey(const ValueKey('ev_trip_over_limit_message')),
          findsNothing);
      expect(h.calls, hasLength(1));
      expect(h.calls.single.stops.map((s) => s.lat).toList(),
          [_lat(100), _lat(200), _lat(300)]);
      expect(h.calls.single.destLat, closeTo(_lat(640), 1e-12));
      // Do'stona xabar (kalit - tarjima ulanmagan) va "Keyingi to'xtashlar".
      expect(find.text('ev_trip_nav_sent_first'), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_trip_next_chip')), findsOneWidget);
    });
    testWidgets('asosiylar chegarani to\'ldirsa (max 2, 2 asosiy): xabarsiz, '
        'ochiladi', (tester) async {
      final h =
          await _pump(tester, plan: _planWithBackups(), maxWaypoints: 2);
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls.single.stops.map((s) => s.lat).toList(),
          [_lat(200), _lat(400)]);
      expect(find.byKey(const ValueKey('ev_trip_over_limit_message')),
          findsNothing);
    });

    testWidgets('reja tayyor emas (uzilish), marshrut bor: tanlov bo\'sh, '
        'faqat manzilga', (tester) async {
      final h = await _pump(tester,
          plan: _planWithBackups(status: EvTripPlanStatus.gapTooLarge));
      expect(
          tester.widget<Material>(find.byKey(_btn)).color, AppColors.primaryDark,
          reason: 'faol');
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(h.calls.single.stops, isEmpty);
      expect(h.calls.single.destLat, closeTo(_lat(640), 1e-12));
    });

    testWidgets('ikki marta tez bosish - bitta chaqiruv', (tester) async {
      final h = await _pump(tester);
      h.hold = Completer<bool>();
      await tester.tap(find.byKey(_btn));
      await tester.pump();
      await tester.tap(find.byKey(_btn));
      await tester.pump();
      expect(h.calls, hasLength(1));
      h.hold!.complete(true);
      await tester.pumpAndSettle();
      // Tugagach yana bosish mumkin.
      h.hold = null;
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(2));
    });
  });

  group('o\'chiq holat va xatolar', () {
    testWidgets('marshrut ham, reja ham yo\'q: kulrang, bosilmaydi, xatosiz',
        (tester) async {
      final h = await _pump(tester, plan: EvTripPlan.empty, route: const []);
      final m = tester.widget<Material>(find.byKey(_btn));
      expect(m.color, isNot(AppColors.primaryDark));
      expect(m.color, const Color(0xFFBDBDBD));
      await tester.tap(find.byKey(_btn), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.calls, isEmpty);
      expect(tester.takeException(), isNull);
      // Hali ham ko'rinadi (matn bilan).
      expect(find.text('ev_trip_navigate'), findsOneWidget);
    });

    testWidgets('manzil koordinatasi yaroqsiz (NaN): kulrang, bosilmaydi',
        (tester) async {
      final h = await _pump(tester, destLat: double.nan);
      expect(tester.widget<Material>(find.byKey(_btn)).color,
          const Color(0xFFBDBDBD));
      await tester.tap(find.byKey(_btn), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ilova ochilmasa (false): do\'stona xabar, ekran ishlaydi',
        (tester) async {
      final h = await _pump(tester);
      h.result = false;
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(find.text('maps_open_failed'), findsOneWidget);
      expect(find.byType(EvTripMapScreen), findsOneWidget);
    });

    testWidgets('chaqiruv xato tashlasa: xabar, halokat yo\'q', (tester) async {
      final h = await _pump(tester);
      h.throwError = true;
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(find.text('maps_open_failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('muvaffaqiyatda xabar chiqmaydi', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(_btn));
      await tester.pumpAndSettle();
      expect(find.text('maps_open_failed'), findsNothing);
    });
  });
}
