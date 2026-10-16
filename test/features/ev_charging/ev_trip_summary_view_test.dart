import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_plan_view.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ev_test_support.dart';

// Reja xulosasi va to'xtash kartochkalarida yo'l vaqti, qo'shiladigan energiya
// va HALOL "kamida" zaryadlash vaqti. A: kalitlar (tarjimasiz), B: haqiqiy
// 3 til matnlari 1.3 shriftda (kesilmaydi, overflow yo'q).

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

EvChargingStation _station(String id, {num? powerKw, String? name}) =>
    EvChargingStation(
      id: id,
      latitude: _lat(100),
      longitude: 60,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: powerKw,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u',
      isActive: true,
      name: name ?? 'ST-$id',
    );

EvTripStop _stop(String id, double along, {num? powerKw}) => EvTripStop(
      station: _station(id, powerKw: powerKw),
      alongKm: along,
      offRouteKm: 0,
      legKm: along,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: const [],
    );

EvTripPlan _plan(List<EvTripStop> stops) => EvTripPlan(
      status: EvTripPlanStatus.ok,
      stops: stops,
      totalKm: 640,
      arrivalSocPercent: 25,
    );

const _car = EvCarSpec(usableBatteryKwh: 60, consumptionKwhPer100Km: 17);

Future<void> _pumpView(
  WidgetTester tester,
  EvTripPlan plan, {
  int routeMinutes = 0,
  EvCarSpec? car,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: EvTripPlanView(
          plan: plan,
          onOpenNavigator: () {},
          routeMinutes: routeMinutes,
          car: car,
        ),
      ),
    ),
  ));
}

const _driveKey = ValueKey('ev_trip_summary_drive_time');
const _chargeKey = ValueKey('ev_trip_summary_charge_time');
const _noteKey = ValueKey('ev_trip_summary_charge_note');
const _stopChargeKey = ValueKey('ev_trip_stop_charge');

String _text(WidgetTester t, Finder f) => t.widget<Text>(f).data!;

class _Source implements EvCarLocationSource {
  @override
  Future<Stream<EvCarFix>?> open() async => const Stream<EvCarFix>.empty();
}

/// Haqiqiy matnlar (til fayli) bilan, 1.3 shrift, tor ekran (360 dp).
Future<void> _pumpReal(
  WidgetTester tester,
  Locale locale,
  Widget Function() home, {
  double scale = 1.3,
  Size size = const Size(360, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      evL10nApp(home: home(), locale: locale, textScale: scale));
  await tester.pumpAndSettle();
}

const _uzCyrl = evUzCyrl;
const _uzLatn = evUzLatn;
const _ru = evRu;
Widget _viewHome(EvTripPlan plan, int minutes, EvCarSpec? car) => Scaffold(
      body: SingleChildScrollView(
        child: EvTripPlanView(
          plan: plan,
          onOpenNavigator: () {},
          routeMinutes: minutes,
          car: car,
        ),
      ),
    );

void main() {
  setUpAll(loadInterFont);

  group('A. reja xulosasi (kalitlar)', () {
    testWidgets('yo\'l vaqti: "13 s 10 daq" shaklida, birliklar kalitdan',
        (tester) async {
      await _pumpView(tester, _plan([_stop('a', 200, powerKw: 120)]),
          routeMinutes: 790, car: _car);
      expect(_text(tester, find.byKey(_driveKey)),
          'ev_trip_drive_time: 13 ev_trip_unit_h 10 ev_trip_unit_min');
    });

    testWidgets('yo\'l vaqti noma\'lum (0) - qator yo\'q', (tester) async {
      await _pumpView(tester, _plan([_stop('a', 200, powerKw: 120)]),
          routeMinutes: 0, car: _car);
      expect(find.byKey(_driveKey), findsNothing);
    });

    testWidgets('zaryadlash vaqti va izoh: quvvat ma\'lum bo\'lsa', (tester) async {
      await _pumpView(tester, _plan([_stop('a', 200, powerKw: 120)]),
          routeMinutes: 100, car: _car);
      expect(find.byKey(_chargeKey), findsOneWidget);
      expect(find.byKey(_noteKey), findsOneWidget);
    });

    testWidgets('hech bir to\'xtashda quvvat noma\'lum - vaqt ham, izoh ham '
        'yo\'q (o\'ylab topilmaydi); energiya baribir ko\'rinadi',
        (tester) async {
      await _pumpView(
          tester, _plan([_stop('a', 200), _stop('b', 400)]),
          routeMinutes: 100, car: _car);
      expect(find.byKey(_chargeKey), findsNothing);
      expect(find.byKey(_noteKey), findsNothing);
      expect(find.byKey(_stopChargeKey), findsNWidgets(2));
      expect(_text(tester, find.byKey(_stopChargeKey).first), '+37 kWh');
    });

    testWidgets('avtomobil yo\'q - energiya ham, zaryadlash vaqti ham yo\'q',
        (tester) async {
      await _pumpView(tester, _plan([_stop('a', 200, powerKw: 120)]),
          routeMinutes: 100);
      expect(find.byKey(_chargeKey), findsNothing);
      expect(find.byKey(_stopChargeKey), findsNothing);
      expect(find.byKey(_driveKey), findsOneWidget);
    });

    testWidgets('to\'xtash kartochkasi: energiya + kamida vaqt kalitlari',
        (tester) async {
      await _pumpView(tester, _plan([_stop('a', 200, powerKw: 120)]),
          car: _car);
      expect(_text(tester, find.byKey(_stopChargeKey)),
          startsWith('+37 kWh · ev_trip_at_least'));
    });
  });

  group('B. haqiqiy matnlar, 1.3 shrift', () {
    final plan = _plan([
      _stop('a', 200, powerKw: 120), // 37.2 kWh / 120 kW -> 19 daq
      _stop('b', 400, powerKw: 60), // 37.2 kWh / 60 kW -> 38 daq
      _stop('c', 500), // quvvat noma'lum
    ]);

    const expected = {
      'uz_Cyrl': (
        drive: 'Йўл вақти: 13 с 10 дақ',
        charge: 'Зарядлаш вақти: камида ~57 дақ',
        stop: '+37 kWh · камида ~19 дақ',
      ),
      'uz_Latn': (
        drive: "Yo'l vaqti: 13 s 10 daq",
        charge: 'Zaryadlash vaqti: kamida ~57 daq',
        stop: '+37 kWh · kamida ~19 daq',
      ),
      'ru': (
        drive: 'Время в пути: 13 ч 10 мин',
        charge: 'Время зарядки: не менее ~57 мин',
        stop: '+37 kWh · не менее ~19 мин',
      ),
    };
    const locales = {'uz_Cyrl': _uzCyrl, 'uz_Latn': _uzLatn, 'ru': _ru};

    for (final entry in locales.entries) {
      testWidgets('${entry.key}: matnlar to\'g\'ri, overflow yo\'q, izoh bor',
          (tester) async {
        await _pumpReal(
            tester, entry.value, () => _viewHome(plan, 790, _car));
        final e = expected[entry.key]!;
        expect(_text(tester, find.byKey(_driveKey)), e.drive);
        // Yig'indi faqat quvvati ma'lum ikki to'xtashdan: 19 + 38 = 57.
        expect(_text(tester, find.byKey(_chargeKey)), e.charge);
        expect(_text(tester, find.byKey(_stopChargeKey).first), e.stop);
        // Quvvat noma'lum uchinchi to'xtash: faqat energiya.
        expect(_text(tester, find.byKey(_stopChargeKey).last), '+37 kWh');
        expect(find.byKey(_noteKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1.3 shrift: ogohlantirish va xulosa matnlari kesilmaydi',
        (tester) async {
      final warnPlan = EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [_stop('a', 200, powerKw: 120)],
        totalKm: 640,
        arrivalSocPercent: 25,
        warnings: const [
          EvTripWarning.connectorUnknown,
          EvTripWarning.noBackup,
          EvTripWarning.unverifiedStops,
        ],
      );
      for (final entry in locales.entries) {
        await _pumpReal(
            tester, entry.value, () => _viewHome(warnPlan, 790, _car));
        expect(tester.takeException(), isNull, reason: entry.key);
        // Hech bir Text qirqilmagan (ellipsis/maxLines yo'q).
        var checked = 0;
        for (final el in find.byType(RichText).evaluate()) {
          final ro = el.renderObject;
          if (ro is RenderParagraph) {
            checked++;
            expect(ro.didExceedMaxLines, isFalse,
                reason: '${entry.key}: ${ro.text.toPlainText()}');
          }
        }
        expect(checked, greaterThan(5), reason: entry.key);
      }
    });
  });

  group('C. xarita varag\'ining yig\'iq satri (peek), 1.3 shrift', () {
    Widget screen(EvTripPlan plan, int minutes) => EvTripMapScreen(
          plan: plan,
          route: [
            for (var i = 0; i <= 100; i += 10) EvRoutePoint(_lat(i * 6.4), 60.0)
          ],
          corridorStations: const [],
          originLat: _lat(0),
          originLng: 60.0,
          destinationLat: _lat(640),
          destinationLng: 60.0,
          onOpenNavigator: () {},
          locationSource: _Source(),
          routeMinutes: minutes,
          car: _car,
          mapBuilder: (context, data) => const ColoredBox(
            color: Color(0xFFCCDDEE),
            child: SizedBox.expand(),
          ),
        );

    const expected = {
      'uz_Cyrl': (
        peek: '3 марта зарядлаш керак · 640 км',
        time: 'Йўл вақти: 13 с 10 дақ',
      ),
      'uz_Latn': (
        peek: '3 marta zaryadlash kerak · 640 km',
        time: "Yo'l vaqti: 13 s 10 daq",
      ),
      'ru': (
        peek: '3 раз нужно зарядиться · 640 км',
        time: 'Время в пути: 13 ч 10 мин',
      ),
    };
    const locales = {'uz_Cyrl': _uzCyrl, 'uz_Latn': _uzLatn, 'ru': _ru};

    for (final entry in locales.entries) {
      testWidgets('${entry.key}: yo\'l vaqti peek da, hammasi kesilmaydi',
          (tester) async {
        final plan = _plan(
            [_stop('a', 100, powerKw: 120), _stop('b', 300), _stop('c', 500)]);
        await _pumpReal(tester, entry.value, () => screen(plan, 790),
            size: const Size(360, 640));
        final peek = find.byKey(const ValueKey('ev_trip_sheet_peek'));
        final e = expected[entry.key]!;
        expect(_text(tester, peek), e.peek);
        final time = find.byKey(const ValueKey('ev_trip_sheet_peek_time'));
        expect(_text(tester, time), e.time);
        for (final f in [peek, time]) {
          final ro = tester.renderObject<RenderParagraph>(
              find.descendant(of: f, matching: find.byType(RichText)));
          expect(ro.didExceedMaxLines, isFalse, reason: entry.key);
        }
        // Yig'iq varaqa sarlavhasi overflow bermaydi.
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('yo\'l vaqti noma\'lum (0): eski matn, vaqtsiz', (tester) async {
      final plan = _plan([_stop('a', 100, powerKw: 120)]);
      await _pumpReal(tester, _uzCyrl, () => screen(plan, 0),
          size: const Size(360, 640));
      expect(_text(tester, find.byKey(const ValueKey('ev_trip_sheet_peek'))),
          '1 марта зарядлаш керак · 640 км');
      expect(find.byKey(const ValueKey('ev_trip_sheet_peek_time')), findsNothing);
    });
  });
}
