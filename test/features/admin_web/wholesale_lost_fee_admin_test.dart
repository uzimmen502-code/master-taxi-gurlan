// Ulgurji admin: yo'qolgan posilka — mas'ul kuryerning yetkazish puli qarzi.
//   adminRecordWholesaleLostFeePayment({orderId, amount, opId, note}) — default codebase.
// Tugma faqat lost + qarz > 0; summa 1..qarz; izoh majburiy; aniq payload; opId shu dialog
// ichidagi qayta urinishda o'zgarmaydi; server xatosi dialogda; muvaffaqiyatdan keyin buyurtma yangilanadi.
//
//   flutter test test/features/admin_web/wholesale_lost_fee_admin_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/screens/wholesale_orders_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_wholesale_orders_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/wholesale_orders_admin.dart';
import 'package:ava_gurlan/features/admin_web/widgets/wholesale_lost_fee_dialog.dart';

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

Map<String, dynamic> _lostDoc({
  String status = 'lost',
  Object? outstanding = 25000,
  Object? anomaly,
  Object? accountId = 'acc_courier_1',
  int paidTotal = 0,
  int refunded = 15000,
}) =>
    {
      'status': status,
      'productTitle': 'Гуруч',
      'goodsTotal': 140000,
      'deliveryFee': 40000,
      'total': 180000,
      'lost': {
        'shipmentId': 'S1',
        'refundTo': 'buyer',
        'refunded': 140000,
        'review': false,
        'deliveryFee': 40000,
        'deliveryFeeRefunded': refunded,
        'deliveryFeeOutstanding': outstanding,
        'deliveryFeePaidTotal': paidTotal,
        'deliveryFeeAnomaly': anomaly,
        'courierAccountId': accountId,
      },
    };

WholesaleOrderAdminView _order([Map<String, dynamic>? d]) => WholesaleOrderAdminView.fromMap('ORD1', d ?? _lostDoc());

Future<void> _open(WidgetTester tester, Future<void> Function(BuildContext) show) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(body: TextButton(onPressed: () => show(context), child: const Text('open'))),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton _confirm(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const ValueKey('lost-fee-confirm')));

void main() {
  group('Model: lost maydonlari', () {
    test('fromMap o\'qiydi; tugma sharti lost + qarz > 0', () {
      final o = _order();
      expect(o.lostFeeOutstanding, 25000);
      expect(o.lostFeeRefunded, 15000);
      expect(o.lostFeePaidTotal, 0);
      expect(o.lostCourierAccountId, 'acc_courier_1');
      expect(o.lostFeeAnomaly, '');
      expect(o.hasLostFeeOutstanding, isTrue);
      expect(o.canRecordLostFeePayment, isTrue);
      expect(o.statusLabel, 'Йўқолди (посилка)');
      expect(o.problems.map((p) => p.kind), ['lost_fee']);
      expect(o.matchesFilter('problem'), isTrue);
      expect(o.matchesFilter('lost'), isTrue);

      expect(_order(_lostDoc(outstanding: 0)).hasLostFeeOutstanding, isFalse);
      expect(_order(_lostDoc(outstanding: 0)).hasProblem, isFalse);
      expect(_order(_lostDoc(outstanding: null)).hasLostFeeOutstanding, isFalse, reason: 'review — null');
      expect(_order(_lostDoc(status: 'in_delivery')).hasLostFeeOutstanding, isFalse, reason: 'faqat lost');
      expect(WholesaleOrderAdminView.fromMap('x', {'status': 'lost'}).hasLostFeeOutstanding, isFalse, reason: 'lost yo\'q');

      final an = _order(_lostDoc(anomaly: 'fee_incident_invalid', accountId: null, refunded: 0, outstanding: 40000));
      expect(an.hasLostFeeOutstanding, isTrue);
      expect(an.canRecordLostFeePayment, isFalse, reason: 'server fee_debt_not_recorded bilan rad etadi');
      expect(an.problems.single.text, contains('fee_incident_invalid'));
      expect(_order(_lostDoc(accountId: '')).canRecordLostFeePayment, isFalse);
    });
  });

  group('Bo\'lim: tugma faqat lost + qarz > 0', () {
    Future<void> pump(WidgetTester tester, WholesaleOrderAdminView o, {VoidCallback? onPay}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: WholesaleLostFeeSection(order: o, onRecordPayment: onPay))),
        ));

    testWidgets('lost + 25 000 — tugma, qarz, kuryer, read-only maydonlar', (tester) async {
      var taps = 0;
      await pump(tester, _order(_lostDoc(paidTotal: 5000)), onPay: () => taps++);
      expect(find.byKey(const ValueKey('lost-fee-pay')), findsOneWidget);
      expect(find.text('Курьер қарзини тўлади'), findsOneWidget);
      expect(find.text('25 000 сўм'), findsOneWidget);
      expect(find.text('acc_courier_1'), findsOneWidget);
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('lost-fee-refunded'))).data, '15 000 сўм');
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('lost-fee-paid-total'))).data, '5 000 сўм');
      expect(find.byKey(const ValueKey('lost-fee-anomaly')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('lost-fee-pay')));
      expect(taps, 1);
    });

    testWidgets('qarz 0 / null (review) / boshqa holat — tugma YO\'Q', (tester) async {
      for (final d in [_lostDoc(outstanding: 0), _lostDoc(outstanding: null), _lostDoc(status: 'in_delivery')]) {
        await pump(tester, _order(d), onPay: () {});
        expect(find.byKey(const ValueKey('lost-fee-pay')), findsNothing, reason: '$d');
      }
      // Boshqa holatda bo'lim umuman chizilmaydi.
      expect(find.text('Йўқолган посилка — етказиш пули'), findsNothing);
    });

    testWidgets('anomaliya — tugma bor, lekin o\'chiq; anomaliya ko\'rsatiladi', (tester) async {
      await pump(tester, _order(_lostDoc(anomaly: 'fee_incident_invalid', accountId: null, refunded: 0, outstanding: 40000)),
          onPay: () {});
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lost-fee-pay'))).onPressed, isNull);
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('lost-fee-anomaly'))).data, 'fee_incident_invalid');
    });
  });

  group('Dialog', () {
    testWidgets('standart summa = qarz; chegaralar 1..qarz; izoh majburiy (≥3)', (tester) async {
      final main = _Fake((n, p) async => {'ok': true});
      final svc = AdminWholesaleOrdersService(demand: _Fake((n, p) async => {}), main: main);
      await _open(tester, (c) => showWholesaleLostFeePaymentDialog(c, svc: svc, order: _order(), newOpId: () => 'op_fixed_1'));

      final amount = find.byKey(const ValueKey('lost-fee-amount'));
      expect(tester.widget<TextField>(amount).controller!.text, '25000');
      expect(_confirm(tester).onPressed, isNull, reason: 'izoh yo\'q');

      await tester.enterText(find.byKey(const ValueKey('lost-fee-note')), 'ab');
      await tester.pump();
      expect(_confirm(tester).onPressed, isNull, reason: '3 belgidan kam');
      await tester.enterText(find.byKey(const ValueKey('lost-fee-note')), '   ab   ');
      await tester.pump();
      expect(_confirm(tester).onPressed, isNull, reason: 'bo\'shliqlar sanalmaydi');
      await tester.enterText(find.byKey(const ValueKey('lost-fee-note')), 'kassaga naqd');
      await tester.pump();
      expect(_confirm(tester).onPressed, isNotNull);

      for (final bad in ['0', '', '25001', '1000000']) {
        await tester.enterText(amount, bad);
        await tester.pump();
        expect(_confirm(tester).onPressed, isNull, reason: 'summa "$bad"');
      }
      expect(find.textContaining('кўпи билан 25 000'), findsOneWidget);
      for (final ok in ['1', '25000', '25 000', '12500']) {
        await tester.enterText(amount, ok);
        await tester.pump();
        expect(_confirm(tester).onPressed, isNotNull, reason: 'summa "$ok"');
      }
      expect(main.calls, isEmpty, reason: 'faqat tasdiqda chaqiriladi');
    });

    testWidgets('aniq payload; server xatosi dialogda; qayta urinishda opId O\'ZGARMAYDI; muvaffaqiyat — yopiladi', (tester) async {
      final errors = <AdminCallableException>[
        const AdminCallableException('failed-precondition', 'exceeds_outstanding', 'Summa qarzdan oshib ketdi',
            details: {'reason': 'exceeds_outstanding', 'outstanding': 10000}),
        const AdminCallableException('failed-precondition', 'debt_mismatch', 'To\'lovni yozib bo\'lmadi',
            details: {'reason': 'debt_mismatch', 'debt': 0}),
      ];
      final main = _Fake((n, p) async {
        if (errors.isNotEmpty) throw errors.removeAt(0);
        return {'ok': true, 'idempotent': false, 'orderId': 'ORD1', 'amount': p['amount'], 'outstanding': 15000, 'paidTotal': 10000};
      });
      final demand = _Fake((n, p) async => {});
      final svc = AdminWholesaleOrdersService(demand: demand, main: main);
      var opIds = 0;
      Map<String, dynamic>? res;
      await _open(tester, (c) async {
        res = await showWholesaleLostFeePaymentDialog(c, svc: svc, order: _order(), newOpId: () => 'op_${++opIds}_abcdef');
      });
      expect(opIds, 1, reason: 'opId dialog ochilganda bir marta');

      await tester.enterText(find.byKey(const ValueKey('lost-fee-amount')), '25000');
      await tester.enterText(find.byKey(const ValueKey('lost-fee-note')), '  kuryer naqd berdi  ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lost-fee-confirm')));
      await tester.pumpAndSettle();

      expect(main.calls.single.$1, 'adminRecordWholesaleLostFeePayment');
      expect(main.calls.single.$2, {'orderId': 'ORD1', 'amount': 25000, 'opId': 'op_1_abcdef', 'note': 'kuryer naqd berdi'});
      expect(main.calls.single.$2['amount'], isA<int>());
      expect(demand.calls, isEmpty, reason: 'default codebase (us-central1), demand emas');
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'xato — dialog yopilmaydi');
      expect(tester.widget<Text>(find.byKey(const ValueKey('lost-fee-error'))).data, contains('қолган: 10 000 сўм'));

      // Admin summani to'g'rilab qayta yuboradi — ўша opId.
      await tester.enterText(find.byKey(const ValueKey('lost-fee-amount')), '10000');
      await tester.pump();
      expect(find.byKey(const ValueKey('lost-fee-error')), findsNothing, reason: 'tahrirda xato tozalanadi');
      await tester.tap(find.byKey(const ValueKey('lost-fee-confirm')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('lost-fee-error'))).data, contains('debt.logistics'));

      await tester.tap(find.byKey(const ValueKey('lost-fee-confirm')));
      await tester.pumpAndSettle();
      expect(main.calls.length, 3);
      expect(main.calls.map((c) => c.$2['opId']).toSet(), {'op_1_abcdef'}, reason: 'qayta urinish — o\'sha opId');
      expect(opIds, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(res?['outstanding'], 15000);
    });

    testWidgets('har yangi dialog — yangi opId (standart UUID, server regex\'iga mos)', (tester) async {
      final main = _Fake((n, p) async => throw const AdminCallableException('permission-denied', '', 'denied'));
      final svc = AdminWholesaleOrdersService(demand: _Fake((n, p) async => {}), main: main);
      await _open(tester, (c) => showWholesaleLostFeePaymentDialog(c, svc: svc, order: _order()));
      Future<void> submit() async {
        await tester.enterText(find.byKey(const ValueKey('lost-fee-note')), 'naqd');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('lost-fee-confirm')));
        await tester.pumpAndSettle();
      }

      await submit();
      expect(tester.widget<Text>(find.byKey(const ValueKey('lost-fee-error'))).data, contains('Рухсат йўқ'));
      await tester.tap(find.text('Бекор'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await submit();
      final ids = main.calls.map((c) => c.$2['opId'] as String).toList();
      expect(ids.length, 2);
      expect(ids[0], isNot(ids[1]));
      for (final id in ids) {
        expect(RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(id), isTrue, reason: id);
      }
    });
  });

  test('Xato matnlari: server sabablari (va topshiriqdagi nomlar) do\'stona matnga', () {
    AdminCallableException e(String reason, [String code = 'failed-precondition']) =>
        AdminCallableException(code, reason, 'raw message');
    final cases = <String, String>{
      'exceeds_outstanding': 'қарздан катта',
      'amount_exceeds_outstanding': 'қарздан катта',
      'nothing_outstanding': 'қарзи қолмаган',
      'no_debt': 'қарзи қолмаган',
      'debt_mismatch': 'debt.logistics',
      'op_id_reused': 'бошқа сумма',
      'not_lost': '«йўқолди» ҳолатида эмас',
      'fee_debt_not_recorded': 'қўлда ҳал',
      'bad_amount': 'мусбат бутун',
      'order_missing': 'топилмади',
    };
    for (final c in cases.entries) {
      final t = wholesaleLostFeeErrorText(e(c.key));
      expect(t, contains(c.value), reason: c.key);
      expect(t, isNot(contains('raw message')), reason: c.key);
    }
    expect(wholesaleLostFeeErrorText(e('', 'permission-denied')), contains('Рухсат йўқ'));
    expect(wholesaleLostFeeErrorText(e('', 'not-found')), contains('deploy'));
    expect(wholesaleLostFeeErrorText(e('something_new')), 'raw message (something_new)', reason: 'umumiy fallback');
  });

  test('Servis: summa ≤ 0 serverga bormaydi', () {
    final main = _Fake((n, p) async => {});
    final svc = AdminWholesaleOrdersService(demand: _Fake((n, p) async => {}), main: main);
    expect(() => svc.recordLostFeePayment(orderId: 'o', amount: 0, opId: 'op_123456', note: 'abc'), throwsArgumentError);
    expect(() => svc.recordLostFeePayment(orderId: 'o', amount: -5, opId: 'op_123456', note: 'abc'), throwsArgumentError);
    expect(main.calls, isEmpty);
  });

  testWidgets('Tafsilot dialogi: to\'lovdan keyin buyurtma qayta o\'qiladi (qarz 0 — tugma yo\'qoladi)', (tester) async {
    final main = _Fake((n, p) async => {'ok': true, 'idempotent': false, 'amount': p['amount'], 'outstanding': 0, 'paidTotal': 25000});
    final svc = AdminWholesaleOrdersService(demand: _Fake((n, p) async => {}), main: main);
    final loaded = <String>[];
    await _open(tester, (c) => showDialog<void>(
          context: c,
          builder: (_) => WholesaleOrderDetailDialog(
            order: _order(),
            svc: svc,
            loadOrder: (id) async {
              loaded.add(id);
              return _order(_lostDoc(outstanding: 0, paidTotal: 25000));
            },
          ),
        ));
    expect(find.byKey(const ValueKey('lost-fee-pay')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lost-fee-pay')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('lost-fee-note')), 'kassaga naqd');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lost-fee-confirm')));
    await tester.pumpAndSettle();

    expect(main.calls.single.$2['amount'], 25000);
    expect(loaded, ['ORD1']);
    expect(find.byKey(const ValueKey('lost-fee-pay')), findsNothing);
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('lost-fee-paid-total'))).data, '25 000 сўм');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('lost-fee-outstanding'))).data, '0 сўм');
    expect(find.textContaining('Тўлов ёзилди: 25 000 сўм'), findsOneWidget);
  });
}
