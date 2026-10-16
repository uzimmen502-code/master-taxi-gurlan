import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_soc_slider.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ev_test_support.dart';

// "Zaryadni yangilash": umumiy slayder vidjeti, varaq (kutilgan zaryadga
// o'rnatilgan), qayta hisob mashinaning hozirgi joyidan, tanlov va "Keyingi
// zaryadlash" raqamlari yangi rejadan, "Qaytarish". Matnlar haqiqiy, katta
// shrift 1.3.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

EvCorridorStation _cs(String id, double along) => EvCorridorStation(
      station: EvChargingStation(
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
      ),
      alongKm: along,
      offRouteKm: 0.5,
    );

List<EvCorridorStation> _corridor() => [
      _cs('a', 100),
      _cs('a2', 230),
      _cs('d', 250),
      _cs('b', 265),
      _cs('e', 300),
      _cs('c', 430),
    ];

EvTripPlan _plan(List<EvCorridorStation> corridor) => EvTripPlanner.plan(
      corridorStations: corridor,
      totalKm: 600,
      car: _car,
      startSocPercent: 100,
    );

List<EvRoutePoint> _route() =>
    [for (var i = 0; i <= 100; i += 10) EvRoutePoint(_lat(i * 6.0), 60.0)];

class _Source implements EvCarLocationSource {
  final ctrl = StreamController<EvCarFix>.broadcast();
  EvCarFix? last;
  @override
  Future<Stream<EvCarFix>?> open() async => Stream<EvCarFix>.multi((c) {
        final l = last;
        if (l != null) c.add(l);
        final sub = ctrl.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });
}

class _H {
  EvTripMapRenderData? last;
  final source = _Source();
}

const _header = ValueKey('ev_trip_sheet_header');
const _undoBtn = ValueKey('ev_trip_undo_button');

Future<_H> _pump(
  WidgetTester tester, {
  Locale locale = evUzLatn,
  double scale = 1.3,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final corridor = _corridor();
  final h = _H();
  await tester.pumpWidget(evL10nApp(
    locale: locale,
    textScale: scale,
    home: EvTripMapScreen(
      plan: _plan(corridor),
      route: _route(),
      corridorStations: corridor,
      originLat: _lat(0),
      originLng: 60.0,
      destinationLat: _lat(600),
      destinationLng: 60.0,
      onOpenNavigator: () {},
      locationSource: h.source,
      car: _car,
      mapBuilder: (context, data) {
        h.last = data;
        return const ColoredBox(
          color: Color(0xFFCCDDEE),
          child: SizedBox.expand(),
        );
      },
    ),
  ));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _fix(WidgetTester tester, _H h, double km, double kmh) async {
  final fix = EvCarFix(lat: _lat(km), lng: 60.0, speedMps: kmh / 3.6);
  h.source.last = fix;
  h.source.ctrl.add(fix);
  await tester.pump();
  await tester.pump();
}

Future<void> _openFromPlanSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(_header));
  await tester.pumpAndSettle();
  final btn = find.byKey(const ValueKey('ev_plan_update_soc'));
  await tester.ensureVisible(btn);
  await tester.pumpAndSettle();
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

/// Slayderni [percent] ga qo'yib "Qayta hisoblash" ni bosadi.
Future<void> _setAndApply(WidgetTester tester, double percent) async {
  final slider = tester.widget<Slider>(find.byKey(const ValueKey('ev_soc_slider')));
  slider.onChanged!(percent);
  await tester.pumpAndSettle();
  final apply = find.byKey(const ValueKey('ev_soc_update_apply'));
  await tester.ensureVisible(apply);
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

String _tr(String key, [Locale locale = evUzLatn]) => evTr(locale, key);
List<String> _ids(_H h) => [for (final s in h.last!.plan.stops) s.station.id];

void main() {
  setUpAll(loadInterFont);

  group('EvSocSliderCard', () {
    test('snap: 5 qadamga, 5..100 oralig\'ida', () {
      expect(EvSocSliderCard.snap(83), 85);
      expect(EvSocSliderCard.snap(82), 80);
      expect(EvSocSliderCard.snap(3), 5);
      expect(EvSocSliderCard.snap(0), 5);
      expect(EvSocSliderCard.snap(120), 100);
      expect(EvSocSliderCard.min, 5);
      expect(EvSocSliderCard.max, 100);
      expect(EvSocSliderCard.divisions, 19);
    });

    testWidgets('qiymat va foiz ko\'rsatiladi, o\'zgarish xabar beriladi',
        (tester) async {
      double value = 60;
      await tester.pumpWidget(evL10nApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EvSocSliderCard(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('60%'), findsOneWidget);
      expect(find.text(_tr('ev_trip_charge_now')), findsOneWidget);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(35);
      await tester.pumpAndSettle();
      expect(find.text('35%'), findsOneWidget);
      final s = tester.widget<Slider>(find.byType(Slider));
      expect(s.min, 5);
      expect(s.max, 100);
      expect(s.divisions, 19);
    });
  });

  group('Zaryadni yangilash - reja varaqasidan', () {
    testWidgets('tugma bor; varaq boshlang\'ich zaryadga o\'rnatilgan (GPS yo\'q)',
        (tester) async {
      await _pump(tester);
      await _openFromPlanSheet(tester);
      expect(find.byKey(const ValueKey('ev_soc_update_title')), findsOneWidget);
      expect(find.text('100%'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('boshlang\'ich qiymat - mashinaning hozirgi joyidagi KUTILGAN '
        'zaryad (50 km: 83% -> 85)', (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 50, 0);
      await _openFromPlanSheet(tester);
      final value = tester.widget<Text>(find.byKey(const ValueKey('ev_soc_value')));
      expect(value.data, '85%');
    });

    testWidgets('matn kiritish yo\'q, "Qayta hisoblash" tugmasi >= 56 dp, 1.3 da sig\'adi',
        (tester) async {
      await _pump(tester);
      await _openFromPlanSheet(tester);
      expect(find.byType(TextField), findsNothing);
      final apply = find.byKey(const ValueKey('ev_soc_update_apply'));
      expect(tester.getSize(apply).height, greaterThanOrEqualTo(56));
      expect(tester.getRect(apply).right, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });
  });

  group('Qayta hisob', () {
    testWidgets('mashina 52 km da, haqiqiy zaryad 30%: qolgan yo\'l shu joydan, '
        'tanlov yangi rejaga ergashadi', (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 52, 0);
      expect(_ids(h), ['b', 'c']);
      expect(h.last!.selectedNumbers.keys, containsAll(['b', 'c']));

      await _openFromPlanSheet(tester);
      await _setAndApply(tester, 30);
      expect(tester.takeException(), isNull);

      final plan = h.last!.plan;
      expect(plan.startSocPercent, 30);
      expect(plan.fromAlongKm, closeTo(52, 0.5),
          reason: 'qayta hisob mashinaning hozirgi joyidan');
      expect(plan.stops.every((s) => s.alongKm > plan.fromAlongKm), isTrue);
      // 30% da ~60 km yetadi: birinchi to'xtash 100 km dagi 'a'.
      expect(_ids(h).first, 'a');
      expect(h.last!.selectedNumbers.containsKey('a'), isTrue);
      expect(h.last!.selectedNumbers.containsKey('b'), isFalse,
          reason: 'eski tavsiya endi rejada yo\'q');
      for (final s in plan.stops) {
        expect(h.last!.selectedNumbers.containsKey(s.station.id), isTrue);
      }
      expect(find.byKey(const ValueKey('ev_trip_undo_chip')), findsOneWidget);
    });

    testWidgets('qo\'lda qo\'shilgan to\'xtash qayta hisobdan keyin ham qoladi',
        (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 52, 0);
      h.last!.onStationTap('a2');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      expect(h.last!.selectedNumbers.containsKey('a2'), isTrue);

      await _openFromPlanSheet(tester);
      await _setAndApply(tester, 30);
      expect(h.last!.selectedNumbers.containsKey('a2'), isTrue);
    });

    testWidgets('"Qaytarish" avvalgi rejani va tanlovni qaytaradi', (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 52, 0);
      final before = h.last!.plan;
      await _openFromPlanSheet(tester);
      await _setAndApply(tester, 30);
      expect(identical(h.last!.plan, before), isFalse);

      await tester.tap(find.byKey(_undoBtn));
      await tester.pumpAndSettle();
      expect(identical(h.last!.plan, before), isTrue);
      expect(h.last!.plan.startSocPercent, 100);
      expect(h.last!.selectedNumbers.keys, containsAll(['b', 'c']));
      expect(h.last!.selectedNumbers.containsKey('a'), isFalse);
    });

    testWidgets('GPS yo\'q: reja o\'z boshlang\'ich joyidan yangi zaryad bilan '
        'qayta hisoblanadi', (tester) async {
      final h = await _pump(tester);
      await _openFromPlanSheet(tester);
      await _setAndApply(tester, 60);
      final plan = h.last!.plan;
      expect(plan.startSocPercent, 60);
      expect(plan.fromAlongKm, 0);
    });

    testWidgets('yo\'l rejimida: "Zaryadni yangilash" kartochkada, raqamlar yangi '
        'rejadan', (tester) async {
      final h = await _pump(tester);
      for (var i = 0; i < 3; i++) {
        await _fix(tester, h, 50.0 + i, 60);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_drive_card')), findsOneWidget);

      final update = find.byKey(const ValueKey('ev_drive_update_soc'));
      expect(update, findsOneWidget);
      expect(tester.getSize(update).height, greaterThanOrEqualTo(44));
      await tester.tap(update);
      await tester.pumpAndSettle();
      await _setAndApply(tester, 30);

      final plan = h.last!.plan;
      final next = plan.stops.first;
      expect(next.station.id, 'a');
      // Kartochkadagi barcha raqamlar yangi rejadan.
      expect(find.text('ST-a'), findsOneWidget);
      expect(find.text('Kelishda ~${next.arriveSocPercent}%'), findsOneWidget);
      final title =
          tester.widget<Text>(find.byKey(const ValueKey('ev_drive_title'))).data!;
      final km = int.parse(RegExp(r'(\d+)(?:\.\d+)? km').firstMatch(title)!.group(1)!);
      expect((km - (next.alongKm - plan.fromAlongKm)).abs(), lessThan(3.1));
      expect(tester.takeException(), isNull);
    });
  });

  group('uch tilda, katta shrift', () {
    for (final entry in {
      'uz_Cyrl': evUzCyrl,
      'uz_Latn': evUzLatn,
      'ru': evRu,
    }.entries) {
      testWidgets('${entry.key}: varaq xatosiz, matnlar o\'z tilida', (tester) async {
        await _pump(tester, locale: entry.value);
        await _openFromPlanSheet(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(_tr('ev_soc_update', entry.value)), findsWidgets);
        expect(find.text(_tr('ev_soc_update_hint', entry.value)), findsOneWidget);
        expect(find.text(_tr('ev_soc_update_apply', entry.value)), findsOneWidget);
      });
    }
  });
}
