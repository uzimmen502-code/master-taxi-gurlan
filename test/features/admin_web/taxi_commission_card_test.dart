import 'package:ava_gurlan/features/admin_web/widgets/taxi_commission_card.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Админ «Такси комиссияси» картаси — сервер `adminGet/SetTaxiCommission`.
void main() {
  Future<void> pump(WidgetTester tester, TaxiCommissionCaller caller) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TaxiCommissionCard(caller: caller)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('percentText: bps → %', () {
    expect(taxiCommissionPercentText(200), '2 %');
    expect(taxiCommissionPercentText(250), '2.50 %');
    expect(taxiCommissionPercentText(5), '0.05 %');
    expect(taxiCommissionPercentText(0), '0 %');
  });

  testWidgets('юклайди ва bps + expectedVersion + reason юборади', (tester) async {
    final calls = <String, Map<String, dynamic>>{};
    await pump(tester, (name, data) async {
      calls[name] = data;
      if (name == 'adminGetTaxiCommission') {
        return {'ok': true, 'bps': 200, 'version': 3, 'configured': true, 'minBps': 0, 'maxBps': 10000};
      }
      return {'ok': true, 'bps': data['bps'], 'version': 4, 'unchanged': false};
    });
    expect(find.textContaining('2 % (200 bps), версия 3'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('taxi_commission_bps')), '250');
    await tester.enterText(find.byKey(const ValueKey('taxi_commission_reason')), 'тест');
    await tester.tap(find.byKey(const ValueKey('taxi_commission_save')));
    await tester.pumpAndSettle();

    expect(calls['adminSetTaxiCommission'], {'bps': 250, 'expectedVersion': 3, 'reason': 'тест'});
    expect(find.textContaining('Янги сафарларга таъсир қилади'), findsWidgets);
    expect(find.textContaining('версия 4'), findsWidgets);
  });

  testWidgets('сабабсиз ва чегарадан ташқари — сақламайди', (tester) async {
    var sets = 0;
    await pump(tester, (name, data) async {
      if (name == 'adminSetTaxiCommission') sets++;
      return {'ok': true, 'bps': 200, 'version': 1, 'configured': true, 'minBps': 0, 'maxBps': 10000};
    });
    await tester.tap(find.byKey(const ValueKey('taxi_commission_save')));
    await tester.pumpAndSettle();
    expect(find.text('Ўзгартириш сабабини ёзинг'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('taxi_commission_bps')), '10001');
    await tester.enterText(find.byKey(const ValueKey('taxi_commission_reason')), 'x');
    await tester.tap(find.byKey(const ValueKey('taxi_commission_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0…10000'), findsWidgets);
    expect(sets, 0);
  });

  testWidgets('VERSION_CONFLICT — хабар ва қайта юклаш', (tester) async {
    var gets = 0;
    await pump(tester, (name, data) async {
      if (name == 'adminGetTaxiCommission') {
        gets++;
        return {'ok': true, 'bps': gets == 1 ? 200 : 300, 'version': gets, 'configured': true, 'minBps': 0, 'maxBps': 10000};
      }
      throw FirebaseFunctionsException(code: 'aborted', message: 'VERSION_CONFLICT');
    });
    await tester.enterText(find.byKey(const ValueKey('taxi_commission_bps')), '250');
    await tester.enterText(find.byKey(const ValueKey('taxi_commission_reason')), 'x');
    await tester.tap(find.byKey(const ValueKey('taxi_commission_save')));
    await tester.pumpAndSettle();
    expect(gets, 2);
    expect(find.textContaining('300 bps'), findsOneWidget);
  });
}
