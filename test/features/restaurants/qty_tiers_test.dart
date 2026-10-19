// Миқдорга чегирма (D-REST-25): соф қоида, меню модели, сават ва сервер билан мослик.
// Ҳақиқий нарх серверда (`functions/test/restaurant_qty_tiers.test.js`, `restaurant_orders_cf.test.js` Q1…Q5);
// бу ерда клиент қоидаси серверники билан БИР ХИЛ эканлиги ва кўрсатиш қулфланади.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/restaurants/domain/qty_tiers.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/widgets/restaurant_cart_sheet.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

QtyTier t(int q, int p) => QtyTier(minQty: q, price: p);

List<QtyTier> _san(int base, Object? raw) => QtyTiers.sanitize(base, raw);
List<Map<String, Object?>> _raw(List<List<Object?>> rows) => [
      for (final r in rows) {'minQty': r[0], 'price': r[1]},
    ];

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('QtyTiers — сервер билан мослик', () {
    test('чегаралар сервердаги MAX_TIERS / MAX_TIER_QTY билан бир хил', () {
      final js = File('functions/restaurant_qty_tiers.js').readAsStringSync();
      expect(int.parse(RegExp(r'const MAX_TIERS = (\d+);').firstMatch(js)!.group(1)!), QtyTiers.maxTiers);
      expect(int.parse(RegExp(r'const MAX_TIER_QTY = (\d+);').firstMatch(js)!.group(1)!), QtyTiers.maxMinQty);
    });

    test('rules: поғона чегаралари (≤3, minQty ≤ 500, биринчиси ≥ 2) клиентдагига тенг', () {
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('d.qtyTiers.size() <= 3'));
      expect(rules, contains('t.minQty <= 500'));
      expect(rules, contains('qtyTierOk(d.qtyTiers[0], 1, d.price)'), reason: 'биринчи минимал сон: 1 дан катта = камида 2');
      expect(QtyTiers.minFirstQty, 2);
    });

    test('3 тилда барча калитлар мавжуд (форма, сават, меню)', () {
      const keys = [
        'restaurants_m_tiers_title', 'restaurants_m_tiers_hint', 'restaurants_m_tiers_add', 'restaurants_m_tiers_from',
        'restaurants_m_tiers_pcs', 'restaurants_m_tiers_price', 'restaurants_m_tiers_preview', 'restaurants_m_tiers_err_fix',
        'restaurants_tier_from', 'restaurants_tier_applied', 'restaurants_tier_next', 'restaurants_qty_discount',
        'restaurants_m_tiers_err_${QtyTiersError.incomplete}', 'restaurants_m_tiers_err_${QtyTiersError.order}', 'restaurants_m_tiers_err_${QtyTiersError.price}',
      ];
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final k in keys) {
          expect((m[k] as String?)?.trim() ?? '', isNotEmpty, reason: '$lang $k');
        }
        expect((m['restaurants_m_tiers_hint'] as String), anyOf(contains('{n}'), isNot(contains('{'))), reason: 'ҳинт плейсхолдерсиз');
        for (final k in ['restaurants_tier_from', 'restaurants_tier_applied', 'restaurants_tier_next']) {
          expect(m[k] as String, contains('{'), reason: '$lang $k плейсхолдер');
        }
      }
    });
  });

  group('QtyTiers.sanitize / unitPriceFor — сервердаги sanitizeTiers билан бир хил қоида', () {
    test('мисол (эга): плов 35 000; 10 тадан 32 000; 30 тадан 30 000', () {
      final tiers = _san(35000, _raw([[10, 32000], [30, 30000]]));
      expect(tiers, [t(10, 32000), t(30, 30000)]);
      QtyTiers.unitPriceFor(35000, tiers, 9);
      expect(QtyTiers.unitPriceFor(35000, tiers, 9), (unitPrice: 35000, tierMinQty: 0));
      expect(QtyTiers.unitPriceFor(35000, tiers, 10), (unitPrice: 32000, tierMinQty: 10));
      expect(QtyTiers.unitPriceFor(35000, tiers, 29), (unitPrice: 32000, tierMinQty: 10));
      expect(QtyTiers.unitPriceFor(35000, tiers, 30), (unitPrice: 30000, tierMinQty: 30));
      expect(12 * QtyTiers.unitPriceFor(35000, tiers, 12).unitPrice, 384000, reason: 'ҳужжатдаги ҳисоб: 12 порция 420 000 → 384 000');
    });

    test('тўғри префикс сақланади, биринчи нотўғридан кейингиси ташланади', () {
      expect(_san(40000, _raw([[10, 38000], [5, 35000], [30, 30000]])), [t(10, 38000)]);
      expect(_san(40000, _raw([[10, 38000], [30, 38000]])), [t(10, 38000)]);
      expect(_san(40000, _raw([[10, 40000]])), isEmpty, reason: 'асосий нархга тенг');
      expect(_san(40000, _raw([[10, 45000]])), isEmpty, reason: 'нарх ОШМАЙДИ');
      expect(_san(40000, _raw([[1, 30000]])), isEmpty);
      expect(_san(40000, _raw([[501, 30000]])), isEmpty);
      expect(_san(40000, _raw([[2, 1]])), [t(2, 1)]);
      expect(_san(40000, _raw([[500, 30000]])), [t(500, 30000)]);
      expect(_san(40000, _raw([[2, 39000], [3, 38000], [4, 37000], [5, 36000]])).length, QtyTiers.maxTiers);
    });

    test('тур хатолари ва нотўғри кириш — поғона эмас', () {
      for (final bad in <Object?>[
        {'minQty': '10', 'price': 100}, {'minQty': 10, 'price': '100'}, {'minQty': 10.5, 'price': 100}, {'minQty': 10, 'price': 99.5},
        {'minQty': -3, 'price': 100}, {'minQty': 10}, {'price': 100}, 5, 'x', null,
      ]) {
        expect(_san(40000, [bad]), isEmpty, reason: '$bad');
      }
      for (final raw in <Object?>[null, 'x', 5, <String, dynamic>{}, const []]) {
        expect(_san(40000, raw), isEmpty);
      }
      expect(_san(0, _raw([[10, 100]])), isEmpty);
      expect(_san(-5, _raw([[10, 100]])), isEmpty);
    });

    test('бутун-қийматли double (Firestore web) қабул қилинади: 10.0 → 10', () {
      expect(_san(40000, [{'minQty': 10.0, 'price': 38000.0}]), [t(10, 38000)]);
    });

    test('nextTier: кейинги поғона; охиргисидан кейин — null', () {
      final tiers = [t(10, 32000), t(30, 30000)];
      expect(QtyTiers.nextTier(tiers, 1), t(10, 32000));
      expect(QtyTiers.nextTier(tiers, 9), t(10, 32000));
      expect(QtyTiers.nextTier(tiers, 10), t(30, 30000));
      expect(QtyTiers.nextTier(tiers, 29), t(30, 30000));
      expect(QtyTiers.nextTier(tiers, 30), isNull);
      expect(QtyTiers.nextTier(const [], 5), isNull);
    });

    test('validate (форма): тўғри — бўш; тартиб ва нарх хатолари алоҳида', () {
      expect(QtyTiers.validate(40000, const []), isEmpty);
      expect(QtyTiers.validate(40000, [t(10, 38000), t(30, 35000)]), isEmpty);
      expect(QtyTiers.validate(40000, [t(1, 38000)]), [QtyTiersError.order]);
      expect(QtyTiers.validate(40000, [t(501, 38000)]), [QtyTiersError.order]);
      expect(QtyTiers.validate(40000, [t(10, 38000), t(10, 35000)]), [QtyTiersError.order]);
      expect(QtyTiers.validate(40000, [t(10, 40000)]), [QtyTiersError.price]);
      expect(QtyTiers.validate(40000, [t(10, 0)]), [QtyTiersError.price]);
      expect(QtyTiers.validate(40000, [t(10, 38000), t(30, 38000)]), [QtyTiersError.price]);
      expect(QtyTiers.validate(40000, [t(5, 50000), t(3, 60000)]).toSet(), {QtyTiersError.order, QtyTiersError.price});
      expect(QtyTiers.validate(0, [t(10, 5)]), [QtyTiersError.price], reason: 'асосий нарх йўқ — поғона нархи ундан кам бўла олмайди');
      expect(QtyTiers.validate(40000, [t(2, 39000), t(3, 38000), t(4, 37000), t(5, 36000)]), contains(QtyTiersError.order));
    });

    test('validate ∧ sanitize мослиги: форма «тўғри» деган рўйхат сервер томонидан ЎЗГАРТИРИЛМАЙДИ', () {
      final valid = [t(2, 39999), t(3, 39998), t(500, 1)];
      expect(QtyTiers.validate(40000, valid), isEmpty);
      expect(_san(40000, [for (final x in valid) x.toMap()]), valid);
    });
  });

  group('MenuItem / CartLine / RestaurantCart', () {
    const r = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');
    final plov = MenuItem.fromMap('plov', {'name': 'Plov', 'price': 35000, 'qtyTiers': _raw([[10, 32000], [30, 30000]])});

    test('fromMap: поғоналар нархга нисбатан тозаланади; йўқ ҳужжат — бўш', () {
      expect(plov.qtyTiers, [t(10, 32000), t(30, 30000)]);
      expect(MenuItem.fromMap('x', {'name': 'A', 'price': 100}).qtyTiers, isEmpty);
      expect(MenuItem.fromMap('x', {'name': 'A', 'price': 100, 'qtyTiers': _raw([[5, 150]])}).qtyTiers, isEmpty, reason: 'нарх ошмайди');
      expect(MenuItem.fromMap('x', {'name': 'A', 'price': 100, 'qtyTiers': 'x'}).qtyTiers, isEmpty);
    });

    test('сават: 9 → 315 000; 10 → 320 000; 12 → 384 000 (чегирма 36 000); «+»/«−» чегарада тўғри ўтади', () {
      final cart = RestaurantCart();
      for (var i = 0; i < 9; i++) {
        cart.add(plov, restaurant: r);
      }
      expect([cart.itemsTotal, cart.qtyDiscountTotal], [315000, 0]);
      cart.add(plov, restaurant: r);
      expect([cart.itemsTotal, cart.qtyDiscountTotal], [320000, 30000]);
      cart.add(plov, restaurant: r);
      cart.add(plov, restaurant: r);
      expect([cart.itemsTotal, cart.qtyDiscountTotal], [384000, 36000]);
      cart.decrement('plov');
      cart.decrement('plov');
      cart.decrement('plov');
      expect(cart.itemsTotal, 9 * 35000, reason: '9 да яна оддий нарх');
      expect(cart.lines.single.unitPrice, 35000);
    });

    test('чегирмасиз таом ўзгармайди; аралаш сават', () {
      const somsa = MenuItem(id: 's', name: 'Somsa', price: 10000);
      final cart = RestaurantCart();
      for (var i = 0; i < 10; i++) {
        cart.add(plov, restaurant: r);
      }
      cart.add(somsa, restaurant: r);
      cart.add(somsa, restaurant: r);
      expect(cart.itemsTotal, 320000 + 20000);
      expect(cart.qtyDiscountTotal, 30000);
      expect(cart.toOrderItems(), [
        {'itemId': 'plov', 'qty': 10},
        {'itemId': 's', 'qty': 2},
      ], reason: 'клиент серверга фақат itemId ва qty юборади — нарх/чегирма эмас');
    });
  });

  group('OrderModel.qtyDiscountTotal', () {
    test('ҳисобда бор — ўқилади; эски буюртмада йўқ — 0', () {
      const o = OrderModel(id: 'o', type: 'restaurant', total: 1, status: 'new', items: [], qtyDiscountTotal: 36000);
      expect(o.qtyDiscountTotal, 36000);
      expect(const OrderModel(id: 'o', type: 'restaurant', total: 1, status: 'new', items: []).qtyDiscountTotal, 0);
    });
  });

  group('Сават варағи', () {
    final plov = MenuItem.fromMap('plov', {'name': 'Plov', 'price': 35000, 'qtyTiers': _raw([[10, 32000], [30, 30000]])});
    const r = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');

    Future<void> pumpSheet(WidgetTester t0, RestaurantCart cart, {double width = 390, double textScale = 1.0}) async {
      t0.view.physicalSize = Size(width * 3, 1800 * 3);
      t0.view.devicePixelRatio = 3;
      addTearDown(t0.view.reset);
      await t0.pumpWidget(l10nApp(
        textScale: textScale,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showRestaurantCartSheet(ctx, cart: cart, restaurant: r, onCheckout: () {}),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t0.tap(find.text('open'));
      await t0.pumpAndSettle();
    }

    testWidgets('поғонагача: «кейинги поғона» маслаҳати; поғонада: қўлланган нарх, чегирма сатри ва жами', (t0) async {
      final cart = RestaurantCart();
      for (var i = 0; i < 8; i++) {
        cart.add(plov, restaurant: r);
      }
      await pumpSheet(t0, cart);
      expect(find.byKey(const ValueKey('cart-tier-next-plov')), findsOneWidget);
      expect((t0.widget(find.byKey(const ValueKey('cart-tier-next-plov'))) as Text).data, contains('2'), reason: 'яна 2 та');
      expect(find.byKey(const ValueKey('cart-tier-applied-plov')), findsNothing);
      expect(find.text(tr('restaurants_qty_discount')), findsNothing);

      cart.add(plov, restaurant: r);
      cart.add(plov, restaurant: r);
      await t0.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart-tier-applied-plov')), findsOneWidget);
      expect((t0.widget(find.byKey(const ValueKey('cart-line-plov'))) as Text).data, '32 000 × 10 = 320 000 ${tr('sum')}');
      expect(find.text(tr('restaurants_qty_discount')), findsOneWidget);
      expect(find.textContaining('-30 000'), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-tier-next-plov')), findsOneWidget, reason: '30 тадан яна арзон');
    });

    testWidgets('охирги поғонада «кейинги» маслаҳат йўқ; тор экран 320 ва шрифт ×2 да синмайди', (t0) async {
      final cart = RestaurantCart();
      for (var i = 0; i < 30; i++) {
        cart.add(plov, restaurant: r);
      }
      await pumpSheet(t0, cart, width: 320, textScale: 2.0);
      expect(t0.takeException(), isNull);
      expect(find.byKey(const ValueKey('cart-tier-next-plov')), findsNothing);
      expect(find.byKey(const ValueKey('cart-tier-applied-plov')), findsOneWidget);
    });
  });
}
