// 4-босқич: «Буюртма бериш» варағи — нарх фақат сервер квотасидан,
// карта фақат квота «мумкин» деса, ҳамён етмаса тўлдириш, муваффақиятда
// буюртма экранига ўтиш, тармоқ хатосидан кейин ўша идемпотентлик калити.
// Тестда `tr` калитнинг ўзини қайтаради.
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_orders_repository.dart';
import 'package:ava_gurlan/features/wholesale/widgets/ship_from_fields.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_checkout_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wholesale_orders_fakes.dart';

const _dest = ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'Мустақиллик кўчаси 5');

class _Harness {
  final demand = FakeFunctions('demand');
  final wallet = FakeFunctions('wallet');
  late final repo = WholesaleOrdersRepository(firestore: FakeDb(), demandFunctions: demand, walletFunctions: wallet);
  String? result;
  String? opened;
  int? topUpAmount;
  bool topUpCalled = false;
}

Future<_Harness> _open(
  WidgetTester tester, {
  required _Harness h,
  int balance = 10000000,
}) async {
  tester.view.physicalSize = const Size(400 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final product = sampleProduct();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              h.result = await showWholesaleCheckoutSheet(
                context,
                product: product,
                pack: product.packById('p2'),
                qty: 2,
                repository: h.repo,
                geoRepository: FakeGeo(),
                balance: Stream.value(balance),
                initialDestination: _dest,
                onTopUp: (_, amount) {
                  h.topUpCalled = true;
                  h.topUpAmount = amount;
                },
                openOrder: (id) => h.opened = id,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _tapConfirm(WidgetTester tester) async {
  final btn = find.byKey(const ValueKey('wholesale-checkout-confirm'));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('квота кўрсатилади: товар, етказиш, жами — фақат сервер рақамлари', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply(goods: 640000, delivery: 45000);
    await _open(tester, h: h);

    final (name, payload) = h.demand.calls.single;
    expect(name, 'quoteWholesaleOrder');
    expect(payload['packId'], 'p2');
    expect(payload['qty'], 2);
    expect((payload['destination'] as Map)['districtId'], 'gurlan');
    expect(find.byKey(const ValueKey('wholesale-quote')), findsOneWidget);
    expect(find.text(formatMoney(640000)), findsOneWidget);
    expect(find.text(formatMoney(45000)), findsOneWidget);
    expect(find.text(formatMoney(685000)), findsOneWidget);
    // Эски сервер (paymentMethods йўқ) — карта варианти умуман йўқ.
    expect(find.byKey(const ValueKey('wholesale-pay-card')), findsNothing);
    expect(find.byKey(const ValueKey('wholesale-pay-wallet')), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const ValueKey('wholesale-checkout-confirm')));
    expect(btn.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('карта мумкин эмас — вариант яширин, сабаб матни бор', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply(
          paymentMethods: {'wallet': true, 'card_on_delivery': false},
          cardReason: 'seller_debt',
        );
    await _open(tester, h: h);
    expect(find.byKey(const ValueKey('wholesale-pay-card')), findsNothing);
    expect(find.text('wholesale_pay_card_unavailable_seller_debt'), findsOneWidget);
  });

  testWidgets('карта мумкин — танланса квота card_on_delivery билан қайта сўралади', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (p) => quoteReply(
          quoteId: 'q-${p['paymentMethod']}',
          paymentMethods: {'wallet': true, 'card_on_delivery': true},
        );
    await _open(tester, h: h);
    expect(find.byKey(const ValueKey('wholesale-due-on-delivery')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wholesale-pay-card')));
    await tester.pumpAndSettle();
    expect(h.demand.calls.length, 2);
    expect(h.demand.calls.last.$2['paymentMethod'], 'card_on_delivery');
    expect(find.byKey(const ValueKey('wholesale-due-on-delivery')), findsOneWidget);
    // Карта буюртмасида ҳамён огоҳлантириши кўрсатилмайди.
    expect(find.byKey(const ValueKey('wallet-balance-info')), findsNothing);
  });

  testWidgets('ҳамён етмайди — сервер рад этади, «Ҳамённи тўлдириш» етишмаган сумма билан', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply(goods: 640000, delivery: 45000);
    h.wallet.handlers['placeWholesaleOrder'] = (_) =>
        throw fnError('failed-precondition', 'insufficient_balance', {'required': 685000, 'balance': 100000});
    await _open(tester, h: h, balance: 100000);
    // Квотадан кейин баланс огоҳлантириши (оқимдан).
    expect(find.byKey(const ValueKey('wallet-balance-short')), findsOneWidget);

    await _tapConfirm(tester);
    expect(h.result, isNull, reason: 'варақ ёпилмайди');
    expect(find.text('wholesale_order_err_insufficient_balance'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wallet-inline-error-topup')));
    await tester.pump();
    expect(h.topUpCalled, isTrue);
    expect(h.topUpAmount, 585000);
  });

  testWidgets('муваффақият: варақ ёпилади, буюртма экрани очилади, калит тўғри шаклда', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply();
    h.wallet.handlers['placeWholesaleOrder'] =
        (_) => {'ok': true, 'orderId': 'o1', 'status': 'placed', 'total': 685000, 'idempotent': false};
    await _open(tester, h: h);
    await _tapConfirm(tester);

    final payload = h.wallet.calls.single.$2;
    expect(payload['quoteId'], 'q1');
    expect(RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(payload['clientRequestId'] as String), isTrue);
    expect(h.result, 'o1');
    expect(h.opened, 'o1');
    expect(find.byKey(const ValueKey('wholesale-checkout-confirm')), findsNothing, reason: 'варақ ёпилди');
  });

  testWidgets('тармоқ хатосидан кейин қайта босилса — ЎША clientRequestId (иккинчи буюртма йўқ)', (tester) async {
    final h = _Harness();
    var n = 0;
    h.demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply();
    h.wallet.handlers['placeWholesaleOrder'] = (_) {
      n++;
      if (n == 1) throw fnError('unavailable', 'unavailable');
      return {'ok': true, 'orderId': 'o1', 'status': 'placed', 'total': 685000, 'idempotent': true};
    };
    await _open(tester, h: h);
    await _tapConfirm(tester);
    expect(find.text('err_network'), findsOneWidget);
    await _tapConfirm(tester);
    expect(h.wallet.calls.length, 2);
    expect(h.wallet.calls[0].$2['clientRequestId'], h.wallet.calls[1].$2['clientRequestId']);
    expect(h.result, 'o1');
  });

  testWidgets('квота эскирган — янги квота ва янги калит, варақ очиқ', (tester) async {
    final h = _Harness();
    var q = 0;
    h.demand.handlers['quoteWholesaleOrder'] = (_) => quoteReply(quoteId: 'q${++q}');
    h.wallet.handlers['placeWholesaleOrder'] = (_) => throw fnError('failed-precondition', 'quote_expired');
    await _open(tester, h: h);
    await _tapConfirm(tester);
    expect(h.demand.calls.length, 2, reason: 'қайта квота');
    expect(find.text('wholesale_order_err_quote_expired'), findsOneWidget);
    expect(h.result, isNull);
  });

  testWidgets('дарвоза ёпиқ (module_internal_only) — тушунарли матн, тасдиқ ўчиқ', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (_) => throw fnError('unavailable', 'module_internal_only');
    await _open(tester, h: h);
    expect(find.text('wholesale_order_err_unavailable'), findsOneWidget);
    expect(find.text('module_internal_only'), findsNothing, reason: 'ички код кўрсатилмайди');
    final btn = tester.widget<FilledButton>(find.byKey(const ValueKey('wholesale-checkout-confirm')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('етказиш нархи белгиланмаган (zone_not_found) — матн, буюртма йўқ', (tester) async {
    final h = _Harness();
    h.demand.handlers['quoteWholesaleOrder'] = (_) => throw fnError('failed-precondition', 'zone_not_found');
    await _open(tester, h: h);
    expect(find.text('wholesale_order_err_delivery_price'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const ValueKey('wholesale-checkout-confirm')));
    expect(btn.onPressed, isNull);
    expect(h.wallet.calls, isEmpty);
  });
}
