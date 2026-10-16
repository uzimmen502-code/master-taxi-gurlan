import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_map_top_overlay.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_plan_view.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `AppLocalizations` делегати уланмаганда `context.tr(key)` калитнинг ўзини
// қайтаради — матнлар калит бўйича текширилади. `GoogleMap` платформа
// кўриниши КЕРАК ЭМАС: харита `mapBuilder` орқали сохта виджет билан
// алмаштирилади ва унга узатилган ҳолат (машина, хиралик, кузатув)
// текширилади. GPS — сохта оқим.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

List<EvRoutePoint> _route() =>
    [for (var i = 0; i <= 100; i += 10) EvRoutePoint(_lat(i.toDouble()), 60.0)];

EvChargingStation _station(String id) => EvChargingStation(
      id: id,
      latitude: _lat(50),
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
      name: 'Бухоро DC',
    );

EvTripStop _stop(String id, double along) => EvTripStop(
      station: _station(id),
      alongKm: along,
      offRouteKm: 0,
      legKm: along,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: const [],
    );

EvTripPlan _okPlan() => EvTripPlan(
      status: EvTripPlanStatus.ok,
      stops: [_stop('s1', 40), _stop('s2', 80)],
      totalKm: 640,
      arrivalSocPercent: 25,
    );

class _Source implements EvCarLocationSource {
  _Source({this.denied = false});
  final bool denied;
  final ctrl = StreamController<EvCarFix>.broadcast();
  int opens = 0;

  @override
  Future<Stream<EvCarFix>?> open() async {
    opens++;
    return denied ? null : ctrl.stream;
  }
}

class _Harness {
  EvTripMapRenderData? last;
  int builds = 0;
  int navigatorTaps = 0;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  EvTripPlan? plan,
  EvCarLocationSource? source,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final h = _Harness();
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EvTripMapScreen(
                  plan: plan ?? _okPlan(),
                  route: _route(),
                  corridorStations: [
                    EvCorridorStation(
                        station: _station('s1'), alongKm: 40, offRouteKm: 0),
                  ],
                  destinationLat: _lat(100),
                  destinationLng: 60.0,
                  onOpenNavigator: () => h.navigatorTaps++,
                  locationSource: source ?? _Source(),
                  mapBuilder: (context, data) {
                    h.last = data;
                    h.builds++;
                    return const ColoredBox(
                      key: ValueKey('fake_map'),
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

void main() {
  testWidgets('харита бутун экранда, юқорида ФАҚАТ орқага тугмаси',
      (tester) async {
    await _pump(tester);

    // Харита бутун экранни эгаллайди (400x800).
    expect(tester.getRect(find.byKey(const ValueKey('fake_map'))),
        const Rect.fromLTWH(0, 0, 400, 800));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.title, isNull);
    expect(appBar.actions, isNull);
    expect(appBar.bottom, isNull);
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.elevation, 0);
    expect(appBar.automaticallyImplyLeading, isFalse);

    // AppBar ичида ягона босиладиган элемент — орқага тугмаси, чап юқорида.
    final inBar = find.descendant(
        of: find.byType(AppBar), matching: find.byType(InkWell));
    expect(inBar, findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.byType(EvMapBackButton)),
        findsOneWidget);
    expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
        findsNothing);
    expect(tester.getRect(find.byType(EvMapBackButton)).left, lessThan(24));
    expect(tester.getRect(find.byType(EvMapBackButton)).top,
        lessThan(24 + kToolbarHeight));
  });

  testWidgets('орқага стрелка экрандан чиқади', (tester) async {
    await _pump(tester);
    expect(find.byType(EvTripMapScreen), findsOneWidget);
    await tester.tap(find.byType(EvMapBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(EvTripMapScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('йиғиқ варақа: бир қатор хулоса «N марта зарядлаш керак · X км»',
      (tester) async {
    await _pump(tester);
    final peek = find.byKey(const ValueKey('ev_trip_sheet_peek'));
    expect(peek, findsOneWidget);
    expect(tester.widget<Text>(peek).data,
        '2 ev_trip_charge_stops · 640 ev_trip_km');
    // Варақа пастда, йиғиқ — баландлиги кичик (экраннинг 1/4 идан кам).
    final sheetTop = tester.getTopLeft(peek).dy;
    expect(sheetTop, greaterThan(800 * 0.75));
  });

  testWidgets('зарядлашга ҳожат йўқ ва узилиш: хулоса матнлари',
      (tester) async {
    await _pump(
      tester,
      plan: const EvTripPlan(
        status: EvTripPlanStatus.noChargingNeeded,
        stops: [],
        totalKm: 200,
        arrivalSocPercent: 33,
      ),
    );
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ev_trip_sheet_peek')))
            .data,
        'ev_trip_no_charging · 200 ev_trip_km');
  });

  testWidgets('узилиш: хулоса сифатида огоҳлантириш', (tester) async {
    await _pump(
      tester,
      plan: EvTripPlan(
        status: EvTripPlanStatus.gapTooLarge,
        stops: [_stop('s1', 40)],
        totalKm: 900,
        arrivalSocPercent: 0,
        gapFromKm: 300,
        gapReachKm: 510,
      ),
    );
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ev_trip_sheet_peek')))
            .data,
        'ev_trip_gap_title');
  });

  testWidgets('варақани очганда режанинг БАРЧА тафсилотлари ўзгаришсиз бор',
      (tester) async {
    final h = await _pump(tester);

    // Режа ичи (EvTripPlanView) аввалдан дарахтда.
    expect(find.byType(EvTripPlanView), findsOneWidget);

    // Варақани юқорига тортамиз.
    await tester.drag(find.byKey(const ValueKey('ev_trip_sheet_header')),
        const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Бухоро DC'), findsNWidgets(2)); // 2 та тўхташ карточкаси
    expect(find.text('ev_trip_open_navigator'), findsOneWidget);
    await tester.ensureVisible(find.text('ev_trip_open_navigator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ev_trip_open_navigator'));
    expect(h.navigatorTaps, 1);
    // Легенда ҳам йўқолмаган.
    expect(find.text('ev_trip_legend_primary'), findsOneWidget);
    expect(find.text('ev_trip_legend_backup'), findsOneWidget);
    expect(find.text('ev_trip_legend_other'), findsOneWidget);
  });

  testWidgets('сарлавҳа босилса варақа очилади/йиғилади', (tester) async {
    await _pump(tester);
    final header = find.byKey(const ValueKey('ev_trip_sheet_header'));
    final y0 = tester.getTopLeft(header).dy;
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, lessThan(y0 - 100));
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, closeTo(y0, 2));
  });

  group('жонли машина (сохта GPS оқими)', () {
    testWidgets('нуқта келса маркер ҳолати харитага узатилади, ўтилгани хира',
        (tester) async {
      final s = _Source();
      final h = await _pump(tester, source: s);
      expect(h.last!.carLat, isNull);
      expect(h.last!.progress, isNull);

      s.ctrl.add(
          EvCarFix(lat: _lat(35), lng: 60.0, headingDeg: 20, speedMps: 15));
      await tester.pump();
      await tester.pump();

      expect(h.last!.carLat, closeTo(_lat(35), 1e-9));
      expect(h.last!.carHeading, 20);
      final p = h.last!.progress!;
      expect(p.alongKm, closeTo(35, 0.1));
      expect(p.hasPassed, isTrue);
      expect(p.hasRemaining, isTrue);
      expect(p.isOnRoute, isTrue);

      // Машина олдинга юрди — ўтилган қисм ортади.
      s.ctrl.add(
          EvCarFix(lat: _lat(60), lng: 60.0, headingDeg: 20, speedMps: 15));
      await tester.pump();
      await tester.pump();
      expect(h.last!.progress!.alongKm, closeTo(60, 0.1));
    });

    testWidgets('GPS рухсати йўқ: маркер ҳам, тугма ҳам йўқ, хато йўқ',
        (tester) async {
      final s = _Source(denied: true);
      final h = await _pump(tester, source: s);
      await tester.pump();
      expect(h.last!.carLat, isNull);
      expect(find.byIcon(Icons.my_location_rounded), findsNothing);
      expect(find.byType(EvTripMapScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(s.opens, 1, reason: 'рухсат/оқим такрор сўралмайди');
    });

    testWidgets(
        '«машинага қайтиш» тугмаси: GPS нуқтасидан кейин пайдо бўлади, '
        'босилса кузатув ёқилади, харитани сурса — ўчади', (tester) async {
      final s = _Source();
      final h = await _pump(tester, source: s);

      // GPS ҳали йўқ — тугма йўқ.
      expect(find.byIcon(Icons.my_location_rounded), findsNothing);
      expect(h.last!.follow, isFalse);

      s.ctrl.add(EvCarFix(lat: _lat(10), lng: 60.0));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      expect(h.last!.follow, isFalse, reason: 'аввал бутун маршрут кўринади');

      await tester.tap(find.byIcon(Icons.my_location_rounded));
      await tester.pump();
      expect(h.last!.follow, isTrue);
      expect(
        find.descendant(
          of: find.byTooltip('ev_trip_recenter'),
          matching: find.byIcon(Icons.navigation_rounded),
        ),
        findsOneWidget,
      );

      // Фойдаланувчи харитани сурди — кузатув тўхтайди (камера курашмайди).
      h.last!.onUserGesture();
      await tester.pump();
      expect(h.last!.follow, isFalse);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);

      // Кузатув ўчиқ пайтда ҳам машина маркери янгиланаверади.
      s.ctrl.add(EvCarFix(lat: _lat(20), lng: 60.0));
      await tester.pump();
      await tester.pump();
      expect(h.last!.carLat, closeTo(_lat(20), 1e-9));
      expect(h.last!.follow, isFalse);
    });

    testWidgets(
        'машина йўлдан жуда узоқда: "йўлда эмас" — хиралаштириш қўлланмайди',
        (tester) async {
      final s = _Source();
      final h = await _pump(tester, source: s);
      s.ctrl.add(EvCarFix(lat: _lat(50), lng: 61.0)); // ~84 км шарқда
      await tester.pump();
      await tester.pump();
      expect(h.last!.carLat, isNotNull);
      expect(h.last!.progress, isNotNull);
      expect(h.last!.progress!.isOnRoute, isFalse);
    });

    testWidgets('оқим хато берса — экран ишлайверади', (tester) async {
      final s = _Source();
      final h = await _pump(tester, source: s);
      s.ctrl.add(EvCarFix(lat: _lat(10), lng: 60.0));
      await tester.pump();
      s.ctrl.addError(StateError('gps lost'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(h.last!.carLat, isNotNull, reason: 'охирги маълум нуқта қолади');
    });
  });

  testWidgets('харита режа ва манзилни олади (маркерлар EvTripMapView да)',
      (tester) async {
    final h = await _pump(tester);
    expect(h.last!.route.length, 11);
    expect(h.last!.corridorStations, hasLength(1));
    expect(h.last!.plan.chargeStopCount, 2);
    expect(h.last!.destinationLat, closeTo(_lat(100), 1e-9));
    // Харита пастдан варақа баландлигича, юқоридан тулбар тагида.
    expect(h.last!.padding.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(h.last!.padding.bottom, greaterThan(0));
  });
}
