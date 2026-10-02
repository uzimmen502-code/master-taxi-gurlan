import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_plan_view.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `AppLocalizations` делегати уланмаганда `context.tr(key)` калитнинг
// ўзини қайтаради (`ev_station_card_test.dart`даги нақш билан бир хил) —
// шунинг учун текширувлар калит матни бўйича ёзилган.

EvChargingStation _station({
  String id = 's1',
  String? name = 'Бухоро DC',
  String status = 'working',
  String verificationStatus = 'verified',
  int confirmationCount = 2,
  String? sourceType,
}) =>
    EvChargingStation(
      id: id,
      latitude: 39.77,
      longitude: 64.42,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: 60,
      status: status,
      verificationStatus: verificationStatus,
      confirmationCount: confirmationCount,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: name,
      sourceType: sourceType,
    );

EvTripStop _stop({
  EvChargingStation? station,
  double alongKm = 300,
  double legKm = 300,
  List<EvTripBackup> backups = const [],
}) =>
    EvTripStop(
      station: station ?? _station(),
      alongKm: alongKm,
      offRouteKm: 0,
      legKm: legKm,
      arriveSocPercent: 18,
      departSocPercent: 80,
      backups: backups,
    );

Future<void> _pump(WidgetTester tester, EvTripPlan plan) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EvTripPlanView(plan: plan, onOpenNavigator: () {}),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('режа тайёр — тўхташлар ва навигатор тугмаси кўринади',
      (tester) async {
    await _pump(
      tester,
      EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [_stop(), _stop(station: _station(id: 's2'), alongKm: 600)],
        totalKm: 900,
        arrivalSocPercent: 25,
      ),
    );

    expect(find.text('Бухоро DC'), findsNWidgets(2));
    expect(find.textContaining('2 ev_trip_charge_stops'), findsOneWidget);
    expect(find.text('ev_trip_open_navigator'), findsOneWidget);
    expect(find.textContaining('900'), findsOneWidget);
    expect(find.text('ev_trip_gap_title'), findsNothing);
  });

  testWidgets('узилиш — огоҳлантириш чиқади, навигатор тугмаси ЙЎҚ',
      (tester) async {
    await _pump(
      tester,
      EvTripPlan(
        status: EvTripPlanStatus.gapTooLarge,
        stops: [_stop()],
        totalKm: 900,
        arrivalSocPercent: 0,
        gapFromKm: 300,
        gapReachKm: 510,
        gapNextStationKm: 700,
      ),
    );

    expect(find.text('ev_trip_gap_title'), findsOneWidget);
    expect(find.text('ev_trip_gap_body'), findsOneWidget);
    // Навигаторда очиш таклиф қилинмайди — режа тўлиқ эмас.
    expect(find.text('ev_trip_open_navigator'), findsNothing);
    expect(find.textContaining('700'), findsOneWidget);
  });

  testWidgets('узилишда кейинги станция бўлмаса — бошқа матн', (tester) async {
    await _pump(
      tester,
      const EvTripPlan(
        status: EvTripPlanStatus.gapTooLarge,
        stops: [],
        totalKm: 900,
        arrivalSocPercent: 0,
        gapFromKm: 0,
        gapReachKm: 270,
      ),
    );

    expect(find.textContaining('ev_trip_gap_none'), findsOneWidget);
    expect(find.text('ev_trip_open_navigator'), findsNothing);
  });

  testWidgets('зарядлашга ҳожат йўқ — тўхташ карточкаси йўқ', (tester) async {
    await _pump(
      tester,
      const EvTripPlan(
        status: EvTripPlanStatus.noChargingNeeded,
        stops: [],
        totalKm: 200,
        arrivalSocPercent: 33,
      ),
    );

    expect(find.text('ev_trip_no_charging'), findsOneWidget);
    expect(find.text('Бухоро DC'), findsNothing);
    expect(find.text('ev_trip_open_navigator'), findsNothing);
  });

  testWidgets('текширилмаган импорт нуқтаси белгиланади', (tester) async {
    await _pump(
      tester,
      EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [
          _stop(
            station: _station(
              status: 'unknown',
              verificationStatus: 'imported',
              confirmationCount: 0,
              sourceType: 'import',
            ),
          ),
        ],
        totalKm: 400,
        arrivalSocPercent: 30,
        warnings: const [EvTripWarning.unverifiedStops],
      ),
    );

    expect(find.text('ev_trip_unverified'), findsOneWidget);
    expect(find.text(EvTripWarning.unverifiedStops), findsOneWidget);
  });

  testWidgets('заҳира вариантлар ишораси билан кўрсатилади', (tester) async {
    await _pump(
      tester,
      EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [
          _stop(backups: [
            EvTripBackup(
              station: _station(id: 'b1', name: 'Қоракўл AC'),
              alongKm: 252,
              offRouteKm: 1,
              deltaKm: -48,
            ),
            EvTripBackup(
              station: _station(id: 'b2', name: 'Ғиждувон DC'),
              alongKm: 341,
              offRouteKm: 2,
              deltaKm: 41,
            ),
          ]),
        ],
        totalKm: 400,
        arrivalSocPercent: 30,
      ),
    );

    expect(find.text('ev_trip_backup'), findsOneWidget);
    // Олдингиси «−», кейингиси «+» белгиси билан.
    expect(find.textContaining('Қоракўл AC  (−48'), findsOneWidget);
    expect(find.textContaining('Ғиждувон DC  (+41'), findsOneWidget);
  });

  testWidgets('номсиз станция — умумий ном ишлатилади', (tester) async {
    await _pump(
      tester,
      EvTripPlan(
        status: EvTripPlanStatus.ok,
        stops: [_stop(station: _station(name: null))],
        totalKm: 400,
        arrivalSocPercent: 30,
      ),
    );

    expect(find.text('ev_trip_station'), findsOneWidget);
  });
}
