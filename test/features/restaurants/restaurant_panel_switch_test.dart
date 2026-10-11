// D-REST-15: бир эга бир нечта кафе — панелда алмаштириш, маълумотлар
// аралашмаслиги ва обуналар тўғри бекор қилиниши (ортиқча Firestore
// listener йўқ). Ҳар `watch*` чақируви Firestore каби ЯНГИ single-subscription
// оқим қайтаради; `onListen`/`onCancel` орқали фаол обуналар саналади.

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

  /// Барча `watch*` чақируvлари — `method:id`, тартиб билан.
  final log = <String>[];

  /// Ҳозир фаол (бекор қилинмаган) обуналар сони — `method:id` бўйича.
  final active = <String, int>{};

  int get activeTotal => active.values.fold(0, (a, b) => a + b);
  Iterable<String> get activeKeys => active.entries.where((e) => e.value > 0).map((e) => e.key);

  Stream<T> _stream<T>(String key, T value) {
    log.add(key);
    late final StreamController<T> c;
    c = StreamController<T>(
      onListen: () {
        active[key] = (active[key] ?? 0) + 1;
        c.add(value);
      },
      onCancel: () {
        active[key] = (active[key] ?? 0) - 1;
      },
    );
    return c.stream;
  }

  @override
  Stream<Restaurant?> watchRestaurant(String id) => _stream('restaurant:$id', restaurants[id]);

  @override
  Stream<List<Restaurant>> watchMine(String ownerUid) =>
      _stream('mine:$ownerUid', restaurants.values.where((r) => r.ownerUid == ownerUid).toList(growable: false));

  @override
  Stream<List<OrderModel>> watchRestaurantOrders(String restaurantId, {int limit = 100}) =>
      _stream('orders:$restaurantId', orders[restaurantId] ?? const <OrderModel>[]);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) =>
      _stream('categories:$restaurantId', const <MenuCategory>[]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => _stream('menu:$restaurantId', const <MenuItem>[]);

  @override
  Stream<Map<String, dynamic>?> watchPaymentDetails(String restaurantId) =>
      _stream<Map<String, dynamic>?>('payment:$restaurantId', null);

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

/// Варақ орқали `name` кафесига ўтиш.
Future<void> _switchTo(WidgetTester t, String currentName, String targetName) async {
  await t.tap(find.text(currentName));
  await t.pumpAndSettle();
  await t.tap(find.text(targetName).last);
  await t.pumpAndSettle();
}

/// Панел очиқ ҳолатда кутиладиган фаол обуналар: ресторан 1, меники 1,
/// буюртмалар 2 (Буюртмалар + Ҳисобот таблари), категория 1, меню 1.
/// `payment` — `.first` билан ўқилади, тугагач ўзи ёпилади (0).
Map<String, int> _expectedActive(String rid, String owner) => {
      'restaurant:$rid': 1,
      'mine:$owner': 1,
      'orders:$rid': 2,
      'categories:$rid': 1,
      'menu:$rid': 1,
    };

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

    // Almashtirishdan keyin barcha obunalar faqat B uchun.
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

  testWidgets('obunalar: ochilganda aniq to\'plam; tab almashuvi yangi listener ochmaydi', (tester) async {
    final repo = _FakeRepo({'a': _r('a', 'Osh markazi'), 'b': _r('b', 'Somsa uyi')});
    await _pump(tester, repo, 'a');

    expect(Map.fromEntries(repo.active.entries.where((e) => e.value > 0)), _expectedActive('a', 'owner1'));
    expect(repo.log.where((e) => e == 'payment:a').length, 1);

    // Pastki navigatsiya: 4 ta tab bo'ylab yurish — hech qanday yangi watch* chaqiruvi yo'q.
    final calls = repo.log.length;
    for (final i in [1, 2, 3, 0]) {
      await tester.tap(find.byType(NavigationDestination).at(i));
      await tester.pumpAndSettle();
    }
    expect(repo.log.length, calls, reason: 'tab almashuvi qayta obuna qilmasligi kerak: ${repo.log.sublist(calls)}');
    expect(Map.fromEntries(repo.active.entries.where((e) => e.value > 0)), _expectedActive('a', 'owner1'));
  });

  testWidgets('tez-tez almashtirish A→B→A→B: eski obunalar bekor, faqat joriy kafeniki faol, soni o\'smaydi', (tester) async {
    final repo = _FakeRepo({'a': _r('a', 'Osh markazi'), 'b': _r('b', 'Somsa uyi')});
    await _pump(tester, repo, 'a');
    final baseline = repo.activeTotal;

    await _switchTo(tester, 'Osh markazi', 'Somsa uyi');
    expect(Map.fromEntries(repo.active.entries.where((e) => e.value > 0)), _expectedActive('b', 'owner1'),
        reason: 'A ning hamma obunasi bekor bo\'lishi kerak');

    await _switchTo(tester, 'Somsa uyi', 'Osh markazi');
    expect(Map.fromEntries(repo.active.entries.where((e) => e.value > 0)), _expectedActive('a', 'owner1'));

    await _switchTo(tester, 'Osh markazi', 'Somsa uyi');
    expect(Map.fromEntries(repo.active.entries.where((e) => e.value > 0)), _expectedActive('b', 'owner1'));
    expect(repo.activeTotal, baseline, reason: 'listener soni oshib ketmaydi');

    // Har almashtirishda har bir oqim ro'pa-rost BIR marta ochiladi (6 ta watch*, payment bilan).
    final opens = repo.log.where((e) => e.endsWith(':b')).length;
    expect(opens, 2 * 6, reason: 'B ikki marta ochildi × 6 oqim: ${repo.log}');

    // Ekran yopilganda hammasi bekor.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(repo.activeTotal, 0, reason: 'dispose: ${repo.activeKeys}');
  });
}
