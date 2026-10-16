import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_alternatives.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_alternatives_sheet.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ev_test_support.dart';

// "Almashtirish": reja varag'idagi kartochkadan va xaritadagi stansiya
// varag'idan alternativalar ro'yxati, tanlash -> reja qayta hisoblanadi,
// tanlov yangi rejaga ergashadi, "Qaytarish", uzilish holati, Google Maps'ga
// yuborish holatining qayta hisoblanishi. Matnlar haqiqiy, shrift Inter,
// katta shrift 1.3.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

EvChargingStation _station(String id, double along,
        {num? power = 120, String? occupancy}) =>
    EvChargingStation(
      id: id,
      latitude: _lat(along),
      longitude: 60.0,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: power,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: 'ST-$id',
      occupancy: occupancy,
      occupancyAt: occupancy == null ? null : DateTime.now(),
    );

EvCorridorStation _cs(String id, double along,
        {num? power = 120, String? occupancy}) =>
    EvCorridorStation(
      station: _station(id, along, power: power, occupancy: occupancy),
      alongKm: along,
      offRouteKm: 0.5,
    );

/// 100% dan 600 km: planner tanlovi [b@265, c@430].
List<EvCorridorStation> _corridor() => [
      _cs('a', 100),
      _cs('a2', 230),
      _cs('d', 250),
      _cs('b', 265),
      _cs('e', 300, occupancy: 'free'),
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
  @override
  Future<Stream<EvCarFix>?> open() async => ctrl.stream;
}

class _H {
  EvTripMapRenderData? last;
  final calls = <List<EvWaypoint>>[];
  final source = _Source();
}

const _header = ValueKey('ev_trip_sheet_header');
const _peek = ValueKey('ev_trip_sheet_peek');
const _undoChip = ValueKey('ev_trip_undo_chip');
const _undoBtn = ValueKey('ev_trip_undo_button');

Future<_H> _pump(
  WidgetTester tester, {
  Locale locale = evUzLatn,
  double scale = 1.3,
  int? maxWaypoints,
  EvCarSpec? car = _car,
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
      maxWaypoints: maxWaypoints,
      car: car,
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
  ));
  await tester.pumpAndSettle();
  return h;
}

String _tr(String key, [Locale locale = evUzLatn]) => evTr(locale, key);

List<String> _stopIds(_H h) =>
    [for (final s in h.last!.plan.stops) s.station.id];

/// Reja varag'ini ochib, [index]-kartochkadagi "Almashtirish" tugmasini bosadi.
Future<void> _openFromPlanSheet(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(_header));
  await tester.pumpAndSettle();
  final btn = find.byKey(ValueKey('ev_stop_replace_$index'));
  await tester.ensureVisible(btn);
  await tester.pumpAndSettle();
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String id) async {
  final btn = find.byKey(ValueKey('ev_alt_choose_$id'));
  await tester.ensureVisible(btn);
  await tester.pumpAndSettle();
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadInterFont);

  group('Almashtirish tugmasi', () {
    testWidgets('reja kartochkalarida har to\'xtash uchun; mashina yo\'q bo\'lsa yo\'q',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(_header));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_stop_replace_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_stop_replace_2')), findsOneWidget);
      expect(find.text(_tr('ev_alt_swap')), findsNWidgets(2));
    });

    testWidgets('mashina ma\'lumoti bo\'lmasa (qayta hisob mumkin emas) tugma yo\'q',
        (tester) async {
      await _pump(tester, car: null);
      await tester.tap(find.byKey(_header));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_stop_replace_1')), findsNothing);
    });

    testWidgets('xaritadagi stansiya varag\'i: tavsiya etilganda bor, boshqasida yo\'q',
        (tester) async {
      final h = await _pump(tester);
      h.last!.onStationTap('a2'); // rejaga kirmagan
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_station_sheet_toggle')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('ev_station_sheet_replace')),
          findsNothing);
      await tester.tapAt(const Offset(200, 20)); // varaqani yopish
      await tester.pumpAndSettle();

      h.last!.onStationTap('b'); // reja to'xtashi
      await tester.pumpAndSettle();
      final replace = find.byKey(const ValueKey('ev_station_sheet_replace'));
      expect(replace, findsOneWidget);
      expect(tester.getSize(replace).height, greaterThanOrEqualTo(56));
      await tester.tap(replace);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_alt_title')), findsOneWidget);
    });
  });

  group('Alternativalar varag\'i', () {
    testWidgets('ro\'yxat: hozirgi birinchi + alternativalar, ta\'sir qatorlari, '
        'matn 1.3 da sig\'adi', (tester) async {
      await _pump(tester);
      await _openFromPlanSheet(tester, 1);
      expect(tester.takeException(), isNull);

      // Hozirgi (birinchi) - 'Hozirgi' belgisi, tugma yo'q.
      expect(find.byKey(const ValueKey('ev_alt_tile_b')), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_alt_badge_current')), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_alt_choose_b')), findsNothing);
      // Tavsiya - bitta qatorda.
      expect(find.byKey(const ValueKey('ev_alt_badge_best')), findsOneWidget);

      // Alternativalar: a (zaxira), a2, d, e (uzilish).
      for (final id in ['a2', 'd', 'e']) {
        expect(find.byKey(ValueKey('ev_alt_tile_$id')), findsOneWidget,
            reason: id);
      }
      // Sarlavha/izoh uz_Latn.
      expect(find.text(_tr('ev_alt_title')), findsOneWidget);
      expect(find.text(_tr('ev_alt_hint')), findsOneWidget);
      // Bo'sh belgisi (e da yangi 'free' hisobot).
      expect(find.text(_tr('home_ev_free')), findsOneWidget);
    });

    testWidgets('yetib bo\'lmaydigan variant qizil izoh bilan; ta\'sir qatori yo\'q',
        (tester) async {
      await _pump(tester);
      await _openFromPlanSheet(tester, 1);
      final e = find.byKey(const ValueKey('ev_alt_tile_e'));
      await tester.ensureVisible(e);
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: e,
              matching: find.byKey(const ValueKey('ev_alt_unreachable'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: e, matching: find.byKey(const ValueKey('ev_alt_arrival'))),
          findsNothing);
    });

    testWidgets('ta\'sir: "Yetib kelganda N% (±d%)" aniq planner natijasi',
        (tester) async {
      final h = await _pump(tester);
      final corridor = _corridor();
      final base = _plan(corridor);
      final rows = EvTripAlternatives.build(
        plan: base,
        stopIndex: 0,
        corridor: corridor,
        car: _car,
      );
      final a2 = rows.firstWhere((r) => r.station.id == 'a2');
      await _openFromPlanSheet(tester, 1);
      final tile = find.byKey(const ValueKey('ev_alt_tile_a2'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      final arrival = tester.widget<Text>(find.descendant(
          of: tile, matching: find.byKey(const ValueKey('ev_alt_arrival'))));
      final d = a2.arrivalDeltaPercent!;
      final sign = d == 0 ? '0' : (d < 0 ? '−${-d}' : '+$d');
      expect(arrival.data,
          '${_tr('ev_trip_arrival')} ${a2.arrivalSocPercent}% ($sign%)');
      expect(h.last, isNotNull);
    });

    testWidgets('tanlash: reja almashadi, tanlov ergashadi, "Qaytarish" qaytaradi',
        (tester) async {
      final h = await _pump(tester);
      expect(_stopIds(h), ['b', 'c']);
      expect(h.last!.selectedNumbers.keys, containsAll(['b', 'c']));

      await _openFromPlanSheet(tester, 1);
      await _choose(tester, 'a2');
      expect(tester.takeException(), isNull);

      expect(_stopIds(h).first, 'a2');
      expect(_stopIds(h), isNot(contains('b')));
      expect(h.last!.selectedNumbers.containsKey('a2'), isTrue);
      expect(h.last!.selectedNumbers.containsKey('b'), isFalse);
      expect(h.last!.selectedNumbers.containsKey('c'), isTrue);
      expect(find.byKey(_undoChip), findsOneWidget);
      expect(find.text(_tr('ev_replan_done')), findsOneWidget);

      await tester.tap(find.byKey(_undoBtn));
      await tester.pumpAndSettle();
      expect(_stopIds(h), ['b', 'c']);
      expect(h.last!.selectedNumbers.containsKey('b'), isTrue);
      expect(h.last!.selectedNumbers.containsKey('a2'), isFalse);
      expect(find.byKey(_undoChip), findsNothing);
    });

    testWidgets('haydovchi qo\'shgan qo\'shimcha to\'xtash almashtirishdan keyin ham qoladi',
        (tester) async {
      final h = await _pump(tester);
      // 'd' ni qo'lda qo'shamiz (stansiya varag'i orqali).
      h.last!.onStationTap('d');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_toggle')));
      await tester.pumpAndSettle();
      expect(h.last!.selectedNumbers.containsKey('d'), isTrue);

      await _openFromPlanSheet(tester, 1);
      await _choose(tester, 'a2');
      expect(h.last!.selectedNumbers.containsKey('d'), isTrue);
      expect(h.last!.selectedNumbers.containsKey('a2'), isTrue);

      // Qaytarishda ham.
      await tester.tap(find.byKey(_undoBtn));
      await tester.pumpAndSettle();
      expect(h.last!.selectedNumbers.containsKey('d'), isTrue);
    });

    testWidgets('yetib bo\'lmaydigan variant tanlansa: uzilish ogohlantirishi, qaytarish bor',
        (tester) async {
      final h = await _pump(tester);
      await _openFromPlanSheet(tester, 1);
      await _choose(tester, 'e');

      expect(h.last!.plan.status, EvTripPlanStatus.gapTooLarge);
      expect(tester.widget<Text>(find.byKey(_peek)).data,
          _tr('ev_trip_gap_title'));
      expect(find.byKey(_undoChip), findsOneWidget);

      await tester.tap(find.byKey(_undoBtn));
      await tester.pumpAndSettle();
      expect(h.last!.plan.status, EvTripPlanStatus.ok);
      expect(_stopIds(h), ['b', 'c']);
    });

    testWidgets('ayni stansiya varag\'idan ham almashtirish ishlaydi', (tester) async {
      final h = await _pump(tester);
      h.last!.onStationTap('c');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ev_station_sheet_replace')));
      await tester.pumpAndSettle();
      // c@430 uchun alternativalar: tanlash yo'q, faqat ro'yxat ochilishi.
      expect(find.byKey(const ValueKey('ev_alt_tile_c')), findsOneWidget);
      expect(h.last!.plan.stops, hasLength(2));
    });

    testWidgets('yopilsa (tanlamasdan) hech narsa o\'zgarmaydi', (tester) async {
      final h = await _pump(tester);
      await _openFromPlanSheet(tester, 1);
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(_stopIds(h), ['b', 'c']);
      expect(find.byKey(_undoChip), findsNothing);
    });
  });

  group('Google Maps\'ga yuborish holati', () {
    testWidgets('almashtirgach bo\'laklash qayta hisoblanadi: chip yo\'qoladi, '
        'eslatma chiqadi', (tester) async {
      final h = await _pump(tester, maxWaypoints: 1);
      await tester.tap(find.byKey(const ValueKey('ev_trip_navigate_button')));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(h.calls.single, hasLength(1));
      expect(find.byKey(const ValueKey('ev_trip_next_chip')), findsOneWidget);
      // Xabar (snackbar) varaq sarlavhasini yopib turmasin.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      await _openFromPlanSheet(tester, 1);
      await _choose(tester, 'a2');

      expect(find.byKey(const ValueKey('ev_trip_next_chip')), findsNothing,
          reason: 'eski yuborish holati yangi tanlovdan qayta boshlanadi');
      expect(find.text(_tr('ev_replan_nav_hint')), findsOneWidget);

      // Qayta "Navigatsiya": yangi tanlovning birinchi to'xtashi yuboriladi.
      await tester.tap(find.byKey(const ValueKey('ev_trip_navigate_button')));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(2));
      expect(h.calls[1].single.lat, closeTo(_lat(230), 1e-9));
      expect(find.byKey(const ValueKey('ev_trip_next_chip')), findsOneWidget);
    });
  });

  group('uch tilda, katta shrift', () {
    for (final entry in {
      'uz_Cyrl': evUzCyrl,
      'uz_Latn': evUzLatn,
      'ru': evRu,
    }.entries) {
      testWidgets('${entry.key}: varaq xatosiz, sarlavha o\'z tilida',
          (tester) async {
        await _pump(tester, locale: entry.value);
        await _openFromPlanSheet(tester, 1);
        expect(tester.takeException(), isNull);
        expect(find.text(_tr('ev_alt_title', entry.value)), findsOneWidget);
      });
    }

    testWidgets('1.3 da tanlash tugmalari ekranga sig\'adi va >= 48 dp',
        (tester) async {
      await _pump(tester);
      await _openFromPlanSheet(tester, 1);
      final btn = find.byKey(const ValueKey('ev_alt_choose_a2'));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      final r = tester.getRect(btn);
      expect(r.height, greaterThanOrEqualTo(48));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });
  });

  group('EvTripAlternativesSheet - yakka', () {
    testWidgets('alternativa yo\'q: izoh, faqat hozirgi', (tester) async {
      final corridor = [_cs('a', 100), _cs('b', 265), _cs('c', 430)];
      final plan = _plan(corridor);
      // 'a' b ning zaxirasi; faqat hozirgi qatorni beramiz.
      final rows = EvTripAlternatives.build(
        plan: plan,
        stopIndex: 0,
        corridor: corridor,
        car: _car,
      ).where((r) => r.isCurrent).toList();
      await tester.pumpWidget(evL10nApp(
        textScale: 1.3,
        home: Scaffold(body: EvTripAlternativesSheet(alternatives: rows)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_alt_none')), findsOneWidget);
      expect(find.text(_tr('ev_alt_none')), findsOneWidget);
    });
  });
}
