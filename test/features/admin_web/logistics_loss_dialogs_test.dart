// Admin "Yo'qoldi" / "To'lov yozish" dialoglari: opId qayta urinishda BIR XIL,
// yangi amalda YANGI; xato dialogda ko'rinadi; to'g'ri callable va payload.
//
//   flutter test test/features/admin_web/logistics_loss_dialogs_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_logistics_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/loss_incident.dart';
import 'package:ava_gurlan/features/admin_web/widgets/logistics_loss_dialogs.dart';

class _Fake implements AdminCallable {
  _Fake(this.handler);

  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>) handler;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload) {
    calls.add((name, payload));
    return handler(name, payload);
  }
}

Future<Map<String, dynamic>?> _open(WidgetTester tester, Future<Map<String, dynamic>?> Function(BuildContext) show) async {
  Map<String, dynamic>? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () async => result = await show(context), child: const Text('open')),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('Yo\'qoldi: sabab 3 belgidan kam — serverga bormaydi; xatodan keyin qayta urinish BIR XIL opId', (tester) async {
    var fail = true;
    final demand = _Fake((name, p) async {
      if (fail) {
        throw const AdminCallableException('failed-precondition', 'shipment_not_lossable', 'x');
      }
      return {'ok': true, 'idempotent': false, 'shipmentId': p['shipmentId'], 'goodsValue': 50000};
    });
    final svc = AdminLogisticsService(demand: demand, main: _Fake((n, p) async => {}));
    await _open(tester, (c) => showMarkShipmentLostDialog(c, service: svc, shipmentId: 'SHIP1', label: 'AVA-1'));

    await tester.tap(find.text('Йўқолди деб белгилаш'));
    await tester.pumpAndSettle();
    expect(demand.calls, isEmpty, reason: 'sabab bo\'sh');

    await tester.enterText(find.byType(TextField).first, 'yo\'qoldi');
    await tester.tap(find.text('Йўқолди деб белгилаш'));
    await tester.pumpAndSettle();
    expect(demand.calls.length, 1);
    expect(demand.calls[0].$1, 'adminMarkShipmentLost');
    expect(demand.calls[0].$2['shipmentId'], 'SHIP1');
    expect(demand.calls[0].$2['reason'], 'yo\'qoldi');
    expect(find.textContaining('Фақат йўлдаги'), findsOneWidget, reason: 'xato matni dialogda');

    fail = false;
    await tester.tap(find.text('Йўқолди деб белгилаш'));
    await tester.pumpAndSettle();
    expect(demand.calls.length, 2);
    final op1 = demand.calls[0].$2['opId'] as String;
    final op2 = demand.calls[1].$2['opId'] as String;
    expect(op2, op1, reason: 'bir xil amal qayta urinishi — bir xil opId');
    expect(RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(op1), isTrue);
    expect(find.byType(AlertDialog), findsNothing, reason: 'muvaffaqiyatda yopiladi');
  });

  testWidgets('Yangi dialog — yangi opId', (tester) async {
    final demand = _Fake((name, p) async => {'ok': true, 'goodsValue': 1});
    final svc = AdminLogisticsService(demand: demand, main: _Fake((n, p) async => {}));
    await _open(tester, (c) => showMarkShipmentLostDialog(c, service: svc, shipmentId: 'S', label: 'L'));
    await tester.enterText(find.byType(TextField).first, 'sabab');
    await tester.tap(find.text('Йўқолди деб белгилаш'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sabab');
    await tester.tap(find.text('Йўқолди деб белгилаш'));
    await tester.pumpAndSettle();
    expect(demand.calls.length, 2);
    expect(demand.calls[0].$2['opId'], isNot(demand.calls[1].$2['opId']));
  });

  testWidgets('To\'lov yozish: 0/o\'nli/harf rad; butun so\'m default codebase\'ga ketadi', (tester) async {
    final main = _Fake((name, p) async => {'ok': true});
    final svc = AdminLogisticsService(demand: _Fake((n, p) async => {}), main: main);
    const inc = LossIncident(
      id: 'S1', shipmentId: 'S1', status: 'settled', goodsValue: 100000, refundedNow: 60000, outstanding: 40000,
      trackingNumber: 'AVA-1',
    );
    await _open(tester, (c) => showRecordLostPaymentDialog(c, service: svc, incident: inc));

    // (maydon faqat raqam/bo'shliq qabul qiladi: "1.5" kiritib bo'lmaydi, "abc" bo'shga aylanadi)
    for (final bad in ['0', '', 'abc']) {
      await tester.enterText(find.byType(TextField).first, bad);
      await tester.tap(find.text('Ёзиш'));
      await tester.pumpAndSettle();
      expect(main.calls, isEmpty, reason: '"$bad"');
    }
    expect(find.textContaining('бутун мусбат'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '40 000');
    await tester.pump();
    await tester.tap(find.text('Ёзиш'));
    await tester.pumpAndSettle();
    expect(main.calls.length, 1);
    expect(main.calls[0].$1, 'adminRecordLostParcelPayment');
    expect(main.calls[0].$2['shipmentId'], 'S1');
    expect(main.calls[0].$2['amount'], 40000);
    expect(main.calls[0].$2['amount'], isA<int>());
    expect(main.calls[0].$2['opId'], isA<String>());
    expect(main.calls[0].$2.containsKey('note'), isFalse, reason: 'bo\'sh izoh yuborilmaydi');
  });

  testWidgets('Stage: faqat berilgan maydonlar yuboriladi', (tester) async {
    final demand = _Fake((n, p) async => {
          'ok': true, 'unchanged': false, 'stage': 'pilot', 'testerCount': 1, 'added': 1, 'removed': 0,
          'effectiveWithinSeconds': 60,
        });
    final svc = AdminLogisticsService(demand: demand, main: _Fake((n, p) async => {}));
    final r = await svc.setStage(addTesterIds: ['998901234567']);
    expect(demand.calls.single.$1, 'adminSetLogisticsStage');
    expect(demand.calls.single.$2, {'addTesterIds': ['998901234567']});
    expect(r.stage, 'pilot');
    expect(r.effectiveWithinSeconds, 60);
    await svc.setStage(stage: 'off', reason: ' sabab ');
    expect(demand.calls[1].$2, {'stage': 'off', 'reason': 'sabab'});
  });
}
