import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/driver_home/widgets/active_ride_card.dart';
import 'package:ava_gurlan/models/active_trip.dart';
import 'package:ava_gurlan/models/trip_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TripRequest _ride({DateTime? arrivedAt}) => TripRequest(
      id: 't1',
      userPhone: '998901234567',
      from: 'Гурлан',
      to: 'Урганч',
      taxiType: 'local',
      secsLeft: 0,
      arrivedAt: arrivedAt,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('«Етиб келди» — модель', () {
    test('ActiveTrip: arrivedAt бўлмаса hasArrived false', () {
      const t = ActiveTrip(id: 't1', status: 'accepted');
      expect(t.hasArrived, isFalse);
      // Статус ўзгармаслиги шарт — акс ҳолда мавжуд сўровлар бузиларди.
      expect(t.isAccepted, isTrue);
    });

    test('ActiveTrip: arrivedAt бўлса hasArrived true, статус accepted', () {
      final t = ActiveTrip(
        id: 't1',
        status: 'accepted',
        arrivedAt: DateTime(2026, 1, 1, 10),
      );
      expect(t.hasArrived, isTrue);
      expect(t.isAccepted, isTrue);
      expect(t.status, 'accepted');
    });

    test('TripRequest ҳам arrivedAt ни олиб юради', () {
      expect(_ride().hasArrived, isFalse);
      expect(_ride(arrivedAt: DateTime(2026)).hasArrived, isTrue);
    });
  });

  group('ActiveRideCard', () {
    testWidgets('етиб келмаган — «ЕТИБ КЕЛДИМ» тугмаси бор', (tester) async {
      var arrived = 0;
      await _pump(
        tester,
        ActiveRideCard(
          ride: _ride(),
          onComplete: () {},
          onArrived: () => arrived++,
        ),
      );
      expect(find.text('ЕТИБ КЕЛДИМ'), findsOneWidget);
      await tester.tap(find.text('ЕТИБ КЕЛДИМ'));
      expect(arrived, 1);
    });

    testWidgets('етиб келган — тугма ўрнига тасдиқ', (tester) async {
      await _pump(
        tester,
        ActiveRideCard(
          ride: _ride(arrivedAt: DateTime(2026)),
          onComplete: () {},
          onArrived: () {},
        ),
      );
      expect(find.text('ЕТИБ КЕЛДИМ'), findsNothing);
      expect(find.text('Йўловчи хабардор қилинди'), findsOneWidget);
    });

    testWidgets('onArrived берилмаса тугма кўрсатилмайди', (tester) async {
      await _pump(
        tester,
        ActiveRideCard(ride: _ride(), onComplete: () {}),
      );
      expect(find.text('ЕТИБ КЕЛДИМ'), findsNothing);
    });

    testWidgets('«Якунлаш» ҳар икки ҳолатда ҳам бор', (tester) async {
      for (final at in <DateTime?>[null, DateTime(2026)]) {
        await _pump(
          tester,
          ActiveRideCard(
            ride: _ride(arrivedAt: at),
            onComplete: () {},
            onArrived: () {},
          ),
        );
        expect(find.text('САФАРНИ ЯКУНЛАШ'), findsOneWidget);
      }
    });
  });
}
