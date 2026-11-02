import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/core/utils/idempotency_keys.dart';
import 'package:ava_gurlan/features/business_orders/data/business_order_session.dart';
import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/screens/business_checkout_sheet.dart';
import 'package:ava_gurlan/models/user_address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'business_order_domain_test.dart' show item;
import 'fake_business_orders_repository.dart';

const _addr = UserAddress(mfy: 'Марказ', street: 'Мустақиллик', house: '5', lat: 41.3, lng: 60.1);

class _Harness {
  _Harness() {
    cart = store.cartFor('b1', businessName: 'Дўкон')..add(item('a', price: 5000), 2);
  }

  final repo = FakeBusinessOrdersRepository();
  final store = BusinessCartStore();
  late final BusinessCart cart;
  final placed = <BusinessPlaceResult>[];
  var keySeq = 0;
  UserAddress? address = _addr;
}

Future<_Harness> _pump(WidgetTester tester, [_Harness? h]) async {
  tester.view.physicalSize = const Size(420 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final x = h ?? _Harness();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: BusinessCheckoutSheet(
        cart: x.cart,
        repository: x.repo,
        store: x.store,
        loadProfile: () async => (phone: '998902222222', name: 'Али', address: x.address, walletBalance: 50000),
        editAddress: (ctx, cur) async => _addr,
        keys: IdempotencyKeys(generator: () => 'biz_key_${++x.keySeq}'),
        onPlaced: (ctx, r) => x.placed.add(r),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return x;
}

Finder get _place => find.byKey(const ValueKey('biz_checkout_place'));

FilledButton _placeBtn(WidgetTester t) => t.widget<FilledButton>(_place);

void main() {
  testWidgets('квота сервердан: етказиш, жами, эшик олдида нақд; маҳсулот пули нақд изоҳи', (tester) async {
    final h = await _pump(tester);
    expect(h.repo.calls, contains('quote:b1:1'));
    expect(find.byKey(const ValueKey('biz_checkout_goods_explain')), findsOneWidget);
    expect(find.text('biz_order_goods_cash_explain'), findsOneWidget);
    expect(find.byKey(const ValueKey('biz_checkout_total')), findsOneWidget);
    // нақд етказиш: 10 000 маҳсулот + 8 000 етказиш = 18 000 эшик олдида.
    expect(find.byKey(const ValueKey('biz_checkout_cash_at_door')), findsOneWidget);
    expect(_placeBtn(tester).onPressed, isNotNull);
  });

  testWidgets('манзил йўқ — квота йўқ, тугма ўчиқ; манзил киритилгач — квота', (tester) async {
    final h = _Harness()..address = null;
    await _pump(tester, h);
    expect(h.repo.calls.where((c) => c.startsWith('quote')), isEmpty);
    expect(_placeBtn(tester).onPressed, isNull);
    expect(find.text('biz_order_address_needed'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('biz_checkout_address')));
    await tester.pumpAndSettle();
    expect(h.repo.calls, contains('quote:b1:1'));
    expect(_placeBtn(tester).onPressed, isNotNull);
  });

  testWidgets('тармоқ хатосидан кейин қайта босиш — ЎША идемпотентлик калити; муваффақиятда сават тозаланади', (tester) async {
    final h = await _pump(tester);
    h.repo.placeQueue.addAll([TimeoutException('lost'), const BusinessPlaceResult(orderId: 'o9')]);
    await tester.tap(_place);
    await tester.pumpAndSettle();
    expect(h.placed, isEmpty);
    expect(h.cart.isNotEmpty, isTrue, reason: 'хатода сават сақланади');
    await tester.tap(_place);
    await tester.pumpAndSettle();
    expect(h.repo.placeKeys, hasLength(2));
    expect(h.repo.placeKeys[0], h.repo.placeKeys[1], reason: 'қайта уриниш — ўша калит (сервер иккинчи буюртма очмайди)');
    expect(RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(h.repo.placeKeys.first), isTrue);
    expect(h.placed.single.orderId, 'o9');
    expect(h.cart.isEmpty, isTrue);
    expect(h.store.existing('b1'), isNull);
    expect(h.repo.placeArgs.first['items'], [
      {'itemId': 'a', 'qty': 2},
    ]);
  });

  testWidgets('сават ўзгарса — янги калит; калит зиддиятида ҳам янги калит', (tester) async {
    final h = await _pump(tester);
    h.repo.placeQueue.addAll([
      TimeoutException('lost'),
      const BusinessOrderException('failed-precondition', 'IDEMPOTENCY_KEY_CONFLICT'),
      const BusinessPlaceResult(orderId: 'o2'),
    ]);
    await tester.tap(_place);
    await tester.pumpAndSettle();
    // Биринчи хато хабари ёпилсин (навбатдаги хабар кўринсин).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_cart_plus_a')));
    await tester.pumpAndSettle();
    await tester.tap(_place);
    await tester.pumpAndSettle();
    expect(h.repo.placeKeys[1], isNot(h.repo.placeKeys[0]), reason: 'миқдор ўзгарди — бошқа ният');
    expect(find.text('biz_order_err_idempotency_key_conflict'), findsOneWidget);
    await tester.tap(_place);
    await tester.pumpAndSettle();
    expect(h.repo.placeKeys[2], isNot(h.repo.placeKeys[1]), reason: 'зиддиятдан кейин янги калит');
    expect(h.placed.single.orderId, 'o2');
  });

  testWidgets('ҳамён танланса — deliveryPaymentMethod wallet', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('biz_checkout_pay_wallet')));
    await tester.pumpAndSettle();
    await tester.tap(_place);
    await tester.pumpAndSettle();
    expect(h.repo.placeArgs.single['pay'], 'wallet');
  });

  testWidgets('квота хатоси — дўстона матн (DELIVERY_TOO_FAR {km}), буюртма тугмаси ўчиқ', (tester) async {
    final h = _Harness();
    h.repo.quoteError = const BusinessOrderException('failed-precondition', 'DELIVERY_TOO_FAR', details: {'maxKm': 25});
    await _pump(tester, h);
    expect(find.text('biz_order_err_delivery_too_far'), findsOneWidget);
    expect(_placeBtn(tester).onPressed, isNull);
  });

  testWidgets('охирги қаторни олиб ташлаш — сават бўш, тугма ўчиқ', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('biz_cart_minus_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_cart_minus_a')));
    await tester.pumpAndSettle();
    expect(h.cart.isEmpty, isTrue);
    expect(find.text('biz_order_cart_empty'), findsOneWidget);
    expect(_placeBtn(tester).onPressed, isNull);
  });
}
