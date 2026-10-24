import 'dart:async';

import 'package:ava_gurlan/features/local_taxi/passenger/screens/local_taxi_active_trip_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Faol safar ekrani: safar hujjatini o'qishda xato bo'lsa cheksiz spinner
/// o'rniga chiqish yo'li (qayta urinish / orqaga) bor (audit F-03).
///
/// Lokalizatsiya delegati atayin yo'q — `context.tr` kalitning o'zini qaytaradi.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(
    WidgetTester t,
    Stream<DocumentSnapshot<Map<String, dynamic>>> Function() factory,
  ) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LocalTaxiActiveTripScreen(
                  tripId: 'trip-1',
                  tripStreamFactory: factory,
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump(); // marshrut o'rnatiladi
    await t.pump(const Duration(milliseconds: 500)); // sahifa o'tish animatsiyasi
  }

  testWidgets('oqim xato bersa — xabar, «Qayta urinish» va «Orqaga»', (t) async {
    final ctrls = <StreamController<DocumentSnapshot<Map<String, dynamic>>>>[];
    Stream<DocumentSnapshot<Map<String, dynamic>>> factory() {
      final c = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      ctrls.add(c);
      return c.stream;
    }

    await pumpScreen(t, factory);
    // Birinchi holat: yuklanmoqda.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(ctrls.length, 1);

    ctrls.first.addError(StateError('permission-denied detail'));
    await t.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('local_trip_load_failed'), findsOneWidget);
    // Xom xato matni ko'rinmaydi.
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.text('err_retry'), findsOneWidget);
    expect(find.text('back'), findsOneWidget);

    // «Qayta urinish» oqimni qayta ochadi va yana yuklanish holatiga qaytadi.
    await t.tap(find.text('err_retry'));
    await t.pump();
    expect(ctrls.length, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('local_trip_load_failed'), findsNothing);

    // «Orqaga» ekranni yopadi.
    ctrls.last.addError(StateError('again'));
    await t.pump();
    await t.tap(find.text('back'));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('local_trip_load_failed'), findsNothing);

    // `close()` tinglovchisiz kontrollerda hech qachon tugamaydi — kutmaymiz.
    for (final c in ctrls) {
      unawaited(c.close());
    }
  });
}
