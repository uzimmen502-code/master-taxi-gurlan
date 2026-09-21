import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_station_card.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';

EvChargingStation _station({
  List<String> chargingTypes = const [],
  List<String> connectors = const [],
  num? powerKw,
  num? price,
  String? operatorName,
  String? note,
}) =>
    EvChargingStation(
      id: 's1',
      latitude: 41.55,
      longitude: 60.60,
      geohash: 'abcd',
      chargingTypes: chargingTypes,
      connectors: connectors,
      powerKw: powerKw,
      price: price,
      operatorName: operatorName,
      note: note,
      status: 'unknown',
      verificationStatus: 'community',
      confirmationCount: 0,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
    );

Future<void> _pump(WidgetTester tester, EvChargingStation station) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EvStationCard(
          station: station,
          distanceKm: 1.2,
          onNavigate: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mavjud bo\'lmagan maydonlar ko\'rsatilmaydi', (tester) async {
    await _pump(tester, _station());

    expect(find.textContaining('🔋'), findsNothing);
    expect(find.textContaining('💰'), findsNothing);
    expect(find.textContaining('🏢'), findsNothing);
    expect(find.textContaining('📝'), findsNothing);
    // Masofa doim ko'rsatiladi.
    expect(find.textContaining('1.2 км'), findsOneWidget);
  });

  testWidgets('mavjud maydonlar ko\'rsatiladi', (tester) async {
    await _pump(
      tester,
      _station(
        chargingTypes: const ['DC'],
        connectors: const ['CCS2'],
        powerKw: 120,
        price: 1500,
        operatorName: 'EV Power',
      ),
    );

    expect(find.textContaining('DC'), findsOneWidget);
    expect(find.textContaining('CCS2'), findsOneWidget);
    expect(find.textContaining('120 kW'), findsOneWidget);
    expect(find.textContaining('EV Power'), findsOneWidget);
  });

  testWidgets('ishonchlilik ogohlantirishi doim ko\'rsatiladi', (tester) async {
    await _pump(tester, _station());
    expect(
      find.textContaining('(foydalanuvchilar) tomonidan kiritilgan'),
      findsOneWidget,
    );
  });
}
