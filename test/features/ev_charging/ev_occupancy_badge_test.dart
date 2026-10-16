import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_occupancy_badge.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_plan_view.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_station_sheet.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// "Bo'sh / Band" belgisi: faqat yangi (30 daqiqa) belgi bo'lsa. Qoida
// EvChargingStation.occupancyState da (station card bilan bir xil manba).
// `AppLocalizations` ulanmagan: `context.tr(key)` kalitning o'zini qaytaradi.

EvChargingStation _station({String? occupancy, Duration? ago}) =>
    EvChargingStation(
      id: 's1',
      latitude: 41,
      longitude: 60,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: 60,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: 'Buxoro DC',
      occupancy: occupancy,
      occupancyAt: ago == null ? null : DateTime.now().subtract(ago),
    );

const _free = ValueKey('ev_occupancy_free');
const _busy = ValueKey('ev_occupancy_busy');

Future<void> _pumpBadge(WidgetTester tester, EvChargingStation s) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: EvOccupancyBadge(station: s))),
    ));

Future<void> _pumpPlan(WidgetTester tester, EvChargingStation s) {
  final plan = EvTripPlan(
    status: EvTripPlanStatus.ok,
    stops: [
      EvTripStop(
        station: s,
        alongKm: 300,
        offRouteKm: 0,
        legKm: 300,
        arriveSocPercent: 18,
        departSocPercent: 80,
        backups: const [],
      ),
    ],
    totalKm: 600,
    arrivalSocPercent: 25,
  );
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: EvTripPlanView(plan: plan, onOpenNavigator: () {}),
      ),
    ),
  ));
}

Future<void> _pumpSheet(
  WidgetTester tester,
  EvChargingStation s, {
  EvTripMarkerKind kind = EvTripMarkerKind.other,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: EvTripStationSheet(
        candidate: EvTripCandidate(
            station: s, alongKm: 100, offRouteKm: 1, kind: kind),
        number: null,
        canAdd: true,
        maxWaypoints: 9,
        onToggle: () {},
      ),
    ),
  ));
}

void main() {
  group('EvOccupancyBadge', () {
    testWidgets('yangi "free" (10 daqiqa oldin) - Bo\'sh', (tester) async {
      await _pumpBadge(
          tester, _station(occupancy: 'free', ago: const Duration(minutes: 10)));
      expect(find.byKey(_free), findsOneWidget);
      expect(find.text('home_ev_free'), findsOneWidget);
      expect(find.byKey(_busy), findsNothing);
    });

    testWidgets('yangi "busy" (29 daqiqa oldin) - Band', (tester) async {
      await _pumpBadge(
          tester, _station(occupancy: 'busy', ago: const Duration(minutes: 29)));
      expect(find.byKey(_busy), findsOneWidget);
      expect(find.text('home_ev_busy'), findsOneWidget);
      expect(find.byKey(_free), findsNothing);
    });

    testWidgets('eskirgan (31 daqiqa) - hech narsa', (tester) async {
      await _pumpBadge(
          tester, _station(occupancy: 'free', ago: const Duration(minutes: 31)));
      expect(find.byKey(_free), findsNothing);
      expect(find.byKey(_busy), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('belgi yo\'q (null) - hech narsa', (tester) async {
      await _pumpBadge(tester, _station());
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('holat bor, vaqti yo\'q - hech narsa (yangi deb hisoblanmaydi)',
        (tester) async {
      await _pumpBadge(tester, _station(occupancy: 'free'));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('free/busy dan boshqa qiymat - belgi chizilmaydi',
        (tester) async {
      // Model faqat 'free' | 'busy' ni yozadi; boshqa qiymat bo'lsa ham
      // badge faqat shu ikkitasini chizadi.
      await _pumpBadge(tester,
          _station(occupancy: 'other', ago: const Duration(minutes: 1)));
      expect(find.byKey(_free), findsNothing);
      expect(find.byKey(_busy), findsNothing);
    });
  });

  group('reja ko\'rinishidagi to\'xtash kartochkasi', () {
    testWidgets('yangi belgi - kartochkada Bo\'sh', (tester) async {
      await _pumpPlan(
          tester, _station(occupancy: 'free', ago: const Duration(minutes: 5)));
      expect(find.byKey(_free), findsOneWidget);
    });

    testWidgets('eskirgan va belgisiz - kartochkada yo\'q', (tester) async {
      await _pumpPlan(
          tester, _station(occupancy: 'busy', ago: const Duration(hours: 2)));
      expect(find.byKey(_busy), findsNothing);
      await _pumpPlan(tester, _station());
      expect(find.byKey(_free), findsNothing);
      expect(find.byKey(_busy), findsNothing);
    });
  });

  group('xaritadagi stansiya varag\'i', () {
    testWidgets('yangi belgi - "Band" varaqda ko\'rinadi', (tester) async {
      await _pumpSheet(
          tester, _station(occupancy: 'busy', ago: const Duration(minutes: 3)));
      expect(find.byKey(_busy), findsOneWidget);
    });

    testWidgets('tavsiya belgisi bilan yonma-yon', (tester) async {
      await _pumpSheet(
          tester, _station(occupancy: 'free', ago: const Duration(minutes: 3)),
          kind: EvTripMarkerKind.primary);
      expect(find.byKey(const ValueKey('ev_station_badge_recommended')),
          findsOneWidget);
      expect(find.byKey(_free), findsOneWidget);
    });

    testWidgets('eskirgan - varaqda yo\'q', (tester) async {
      await _pumpSheet(
          tester, _station(occupancy: 'free', ago: const Duration(hours: 1)));
      expect(find.byKey(_free), findsNothing);
      expect(find.byKey(_busy), findsNothing);
    });
  });
}
