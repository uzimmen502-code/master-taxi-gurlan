// D-REST-15: бир эга бир нечта кафе — панелда алмаштириш ва маълумотлар
// аралашмаслиги (ҳар таб фақат жорий ресторан ID'сига обуна бўлади).

import 'dart:async';

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_panel_screen.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements RestaurantsRepository {
  _FakeRepo(this.restaurants, {this.orders = const {}});

  final Map<String, Restaurant> restaurants;
  final Map<String, List<OrderModel>> orders;

  /// Қайси ресторан ID'лари сўралгани — `method:id` кўринишида, тартиб билан.
  final log = <String>[];

  @override
  Stream<Restaurant?> watchRestaurant(String id) {
    log.add('restaurant:$id');
    return Stream.value(restaurants[id]);
  }

  @override
  Stream<List<Restaurant>> watchMine(String ownerUid) {
    log.add('mine:$ownerUid');
    return Stream.value(restaurants.values.where((r) => r.ownerUid == ownerUid).toList(growable: false));
  }

  @override
  Stream<List<OrderModel>> watchRestaurantOrders(String restaurantId, {int limit = 100}) {
    log.add('orders:$restaurantId');
    return Stream.value(orders[restaurantId] ?? const []);
  }

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) {
    log.add('categories:$restaurantId');
    return Stream.value(const []);
  }

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) {
    log.add('menu:$restaurantId');
    return Stream.value(const []);
  }

  @override
  Stream<Map<String, dynamic>?> watchPaymentDetails(String restaurantId) {
    log.add('payment:$restaurantId');
    return Stream.value(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Restaurant _r(String id, String name, {String status = 'approved'}) =>
    Restaurant(id: id, name: name, status: status, ownerUid: 'owner1');

OrderModel _historyOrder(String id, String rid) => OrderModel(
      id: id,
      type: 'restaurant',
      total: 50000,
      status: 'delivered',
      items: const [],
      restaurantId: rid,
      restaurantStatus: RestaurantOrderStatus.delivered,
      itemsTotal: 50000,
    );

Future<void> _pump(WidgetTester t, _FakeRepo repo, String rid) async {
  await t.pumpWidget(MaterialApp(home: RestaurantPanelScreen(restaurantId: rid, repository: repo)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('bitta kafe: sarlavha nomi, almashtirish belgisi yo\'q', (tester) async {
    final repo = _FakeRepo({'a': _r('a', 'Osh markazi')});
    await _pump(tester, repo, 'a');
    expect(find.text('Osh markazi'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
  });

  testWidgets('ikki kafe: sarlavha → varaq (ikkalasi + «yana ochish»), tanlash → panel to\'liq B ga o\'tadi, A ma\'lumoti qolmaydi',
      (tester) async {
    final repo = _FakeRepo(
      {'a': _r('a', 'Osh markazi'), 'b': _r('b', 'Somsa uyi', status: 'applied')},
      orders: {
        'a': [_historyOrder('o1', 'a'), _historyOrder('o2', 'a')],
      },
    );
    await _pump(tester, repo, 'a');

    expect(find.text('Osh markazi'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    // A da 2 ta tarix buyurtmasi — bucket hisobchisida ko'rinadi.
    expect(find.text('restaurants_m_bucket_history 2'), findsOneWidget);
    // Hamma tab A ga obuna.
    expect(repo.log.where((e) => e.endsWith(':b')), isEmpty);

    await tester.tap(find.text('Osh markazi'));
    await tester.pumpAndSettle();
    expect(find.text('restaurants_m_switch_cafe'), findsOneWidget);
    expect(find.text('Somsa uyi'), findsOneWidget);
    expect(find.text('restaurants_m_status_applied'), findsWidgets);
    expect(find.text('restaurants_m_add_another'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget, reason: 'joriy (A) belgilangan');

    final mark = repo.log.length;
    await tester.tap(find.text('Somsa uyi'));
    await tester.pumpAndSettle();

    // Sarlavha va holat B niki; A nomi yo'q.
    expect(find.text('Somsa uyi'), findsOneWidget);
    expect(find.text('Osh markazi'), findsNothing);
    expect(find.text('restaurants_m_pending_note'), findsOneWidget, reason: 'B applied — banner');
    // A ning 2 ta buyurtmasi B panelida ko'rinmaydi.
    expect(find.text('restaurants_m_bucket_history 2'), findsNothing);
    expect(find.text('restaurants_m_bucket_history'), findsOneWidget);

    // Almashtirishdan keyin barcha obunalar faqat B uchun: restaurant, orders (×2 tab), menu, categories, payment.
    final after = repo.log.sublist(mark);
    expect(after.where((e) => e.endsWith(':a')), isEmpty, reason: 'A ga yangi obuna bo\'lmasligi kerak: $after');
    for (final m in ['restaurant', 'orders', 'categories', 'menu', 'payment']) {
      expect(after, contains('$m:b'), reason: '$m B uchun qayta ochilishi kerak: $after');
    }
  });

  testWidgets('varaqda joriy kafe tanlansa — hech narsa o\'zgarmaydi', (tester) async {
    final repo = _FakeRepo({'a': _r('a', 'Osh markazi'), 'b': _r('b', 'Somsa uyi')});
    await _pump(tester, repo, 'a');
    await tester.tap(find.text('Osh markazi'));
    await tester.pumpAndSettle();
    final mark = repo.log.length;
    await tester.tap(find.byIcon(Icons.radio_button_checked));
    await tester.pumpAndSettle();
    expect(find.text('restaurants_m_switch_cafe'), findsNothing);
    expect(find.text('Osh markazi'), findsOneWidget);
    expect(repo.log.length, mark, reason: 'qayta obuna yo\'q');
  });
}
