// 4-босқич: кириш нуқталари дарвозага бўйсунади (42-банд) ва сотувчи
// картаси формасининг локал текшируви.
import 'package:ava_gurlan/features/wholesale/models/wholesale_order.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_order_entries.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

class _GateRepo extends WholesaleOrdersRepository {
  _GateRepo(this._gate, {super.demandFunctions}) : super(firestore: FakeDb());
  final WholesaleOrdersGate _gate;

  @override
  Future<WholesaleOrdersGate> gate() async => _gate;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: AppBar(actions: [child]), body: const SizedBox())));
  await tester.pumpAndSettle();
}

void main() {
  const me = '998900000001';
  const tester1 = WholesaleOrdersGate(enabled: true, stage: 'internal', testerIds: [me]);

  testWidgets('харидор: дарвоза ёпиқ — «Менинг буюртмаларим» йўқ', (tester) async {
    await _pump(tester, WholesaleBuyerOrdersAction(userPhone: me, repository: _GateRepo(WholesaleOrdersGate.closed)));
    expect(find.byKey(const ValueKey('wholesale-my-orders')), findsNothing);
  });

  testWidgets('харидор: internal, синовчи эмас — йўқ; синовчи — бор', (tester) async {
    await _pump(tester,
        WholesaleBuyerOrdersAction(userPhone: '998900000002', repository: _GateRepo(tester1)));
    expect(find.byKey(const ValueKey('wholesale-my-orders')), findsNothing);
    await _pump(tester, WholesaleBuyerOrdersAction(userPhone: me, repository: _GateRepo(tester1)));
    expect(find.byKey(const ValueKey('wholesale-my-orders')), findsOneWidget);
  });

  testWidgets('сотувчи: дарвоза ёқилган бўлса (синовчи бўлмаса ҳам) — «Келган буюртмалар»', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WholesaleSellerOrdersPanel(sellerPhone: '998901111111', repository: _GateRepo(tester1)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wholesale-incoming-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('wholesale-seller-card')), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WholesaleSellerOrdersPanel(
            sellerPhone: '998901111111', repository: _GateRepo(WholesaleOrdersGate.closed)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wholesale-incoming-orders')), findsNothing);
  });

  group('сотувчи картаси — локал текширув', () {
    test('мусбат / манфий / чегара', () {
      expect(WholesaleSellerCardSheet.validate('8600123456789012', 'ALI VALIYEV'), isNull);
      expect(WholesaleSellerCardSheet.validate('8600 1234 5678 9012', 'ALI'), isNull, reason: '3 ҳарф — чегара');
      expect(WholesaleSellerCardSheet.validate('860012345678901', 'ALI'), 'wholesale_seller_card_err_number');
      expect(WholesaleSellerCardSheet.validate('86001234567890123', 'ALI'), 'wholesale_seller_card_err_number');
      expect(WholesaleSellerCardSheet.validate('8600123456789012', ' AL '), 'wholesale_seller_card_err_holder');
    });

    testWidgets('сақлаш: callable рақамлар билан, варақ ёпилади', (tester) async {
      final demand = FakeFunctions('demand');
      demand.handlers['setWholesaleSellerCard'] = (_) => {'ok': true};
      final repo = _GateRepo(tester1, demandFunctions: demand);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWholesaleSellerCardSheet(context, repository: repo),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '8600123456789012');
      await tester.enterText(find.byType(TextField).at(1), 'ALI VALIYEV');
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(demand.calls.single.$1, 'setWholesaleSellerCard');
      expect(demand.calls.single.$2, {'cardNumber': '8600123456789012', 'holderName': 'ALI VALIYEV'});
      expect(find.text('wholesale_seller_card_saved'), findsOneWidget);
    });
  });
}
