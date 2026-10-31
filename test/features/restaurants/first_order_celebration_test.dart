// Эга, 2026-10-31: кафе / уй ошпазига БИРИНЧИ буюртма келганда конфетти — ресторан учун БИР МАРТА.
// Қоида ([FirstOrderDetector]): панел очилгандаги биринчи рўйхат БЎШ ва ундан кейинги биринчи бўш
// бўлмаган рўйхат айнан БИТТА янги (`placed`) буюртма. Эски буюртмалар — ҳеч қачон.
// Локализация делегати уланмаган: `context.tr` калитнинг ўзини қайтаради.

import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/merchant_order_actions.dart';
import 'package:ava_gurlan/features/restaurants/merchant/merchant_orders_tab.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_panel_screen.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderModel _o(String id, String restaurantStatus, {String rid = 'r1'}) => OrderModel(
      id: id,
      type: 'restaurant',
      total: 50000,
      status: 'pending',
      items: const [],
      restaurantId: rid,
      restaurantStatus: restaurantStatus,
      itemsTotal: 50000,
      deliveryMode: 'pickup',
    );

OrderModel _placed(String id, {String rid = 'r1'}) => _o(id, RestaurantOrderStatus.placed, rid: rid);
OrderModel _delivered(String id, {String rid = 'r1'}) => _o(id, RestaurantOrderStatus.delivered, rid: rid);

/// Буюртмалар оқими қўлда бошқарилади: ҳар `watchRestaurantOrders` — янги обуна, уланишда
/// жорий рўйхат дарҳол берилади (Firestore каби); [emit] — барча фаол обуналарга.
class _FakeRepo implements RestaurantsRepository {
  _FakeRepo(this.restaurant, {List<OrderModel>? initial}) : _current = initial;

  final Restaurant restaurant;
  List<OrderModel>? _current;
  final _subs = <StreamController<List<OrderModel>>>[];
  var acceptCalls = 0;

  void emit(List<OrderModel> list) {
    _current = list;
    for (final c in _subs) {
      c.add(list);
    }
  }

  Stream<T> _single<T>(T value) {
    late final StreamController<T> c;
    c = StreamController<T>(onListen: () => c.add(value));
    return c.stream;
  }

  @override
  Stream<List<OrderModel>> watchRestaurantOrders(String restaurantId, {int limit = 100}) {
    late final StreamController<List<OrderModel>> c;
    c = StreamController<List<OrderModel>>(
      onListen: () {
        _subs.add(c);
        final cur = _current;
        if (cur != null) c.add(cur);
      },
      onCancel: () => _subs.remove(c),
    );
    return c.stream;
  }

  @override
  Future<Map<String, dynamic>> accept(String orderId, {int? prepTimeMin}) async {
    acceptCalls++;
    return const {};
  }

  // Панел учун (бошқа таблар).
  @override
  Stream<Restaurant?> watchRestaurant(String id) => _single<Restaurant?>(restaurant);

  @override
  Stream<List<Restaurant>> watchMine(String ownerUid) => _single(<Restaurant>[restaurant]);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) => _single(const <MenuCategory>[]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => _single(const <MenuItem>[]);

  @override
  Stream<Map<String, dynamic>?> watchPaymentDetails(String restaurantId) => _single<Map<String, dynamic>?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Restaurant _r(String id) => Restaurant(id: id, name: 'Osh markazi', status: 'approved', ownerUid: 'owner1');

final _nav = GlobalKey<NavigatorState>();

Future<({_FakeRepo repo, List<int> shown})> _pumpTab(
  WidgetTester t, {
  String rid = 'r1',
  List<OrderModel>? initial = const [],
}) async {
  final repo = _FakeRepo(_r(rid), initial: initial);
  final shown = <int>[];
  await t.pumpWidget(MaterialApp(
    navigatorKey: _nav,
    theme: AppTheme.light,
    home: Scaffold(
      body: MerchantOrdersTab(
        key: ValueKey('tab_$rid'),
        restaurant: repo.restaurant,
        repository: repo,
        playSound: false,
        onShowOrders: () => shown.add(1),
      ),
    ),
  ));
  await t.pump();
  return (repo: repo, shown: shown);
}

/// Оқим янгиланди → кадр → post-frame → `claim` (async) → ойна → кириш анимацияси.
Future<void> _settleDialog(WidgetTester t) async {
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

final _title = find.text('restaurants_m_first_order_title');

Future<void> _tapView(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('celebration_ok')));
  await t.pumpAndSettle();
}

/// Ташқи таймерлар (1 с ҳисоблагич) тест охирида қолмасин.
Future<void> _dispose(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FirstOrderDetector (соф қоида)', () {
    test('мусбат: биринчи рўйхат бўш → кейин битта янги буюртма — шу id, фақат БИР марта', () {
      final d = FirstOrderDetector();
      expect(d.onList(const []), isNull);
      expect(d.onList([_placed('o1')]), 'o1');
      expect(d.onList([_placed('o1')]), isNull, reason: 'қайта қурилишда такрорланмайди');
      expect(d.onList([_placed('o2'), _placed('o1')]), isNull);
    });

    test('манфий: панел очилганда эски буюртмалар бор — кейинги янги буюртма ҳам «биринчи» эмас', () {
      final d = FirstOrderDetector();
      expect(d.onList([_delivered('o0')]), isNull);
      expect(d.onList([_placed('o1'), _delivered('o0')]), isNull);
      expect(d.onList([_placed('o2'), _placed('o1'), _delivered('o0')]), isNull);
    });

    test('манфий: эски очилмаган (placed) буюртма биринчи рўйхатда — табрик йўқ', () {
      final d = FirstOrderDetector();
      expect(d.onList([_placed('o0')]), isNull);
      expect(d.onList([_placed('o0')]), isNull);
    });

    test('чегара: бўш рўйхат такрорланса қоида қуролланган туради', () {
      final d = FirstOrderDetector();
      for (var i = 0; i < 5; i++) {
        expect(d.onList(const []), isNull);
      }
      expect(d.onList([_placed('o1')]), 'o1');
    });

    test('чегара: бўшдан кейин бирданига 2 та буюртма (масалан кешдан бўш, сервердан эскилари) — йўқ ва ўчади', () {
      final d = FirstOrderDetector();
      expect(d.onList(const []), isNull);
      expect(d.onList([_placed('o2'), _placed('o1')]), isNull);
      expect(d.onList([_placed('o3')]), isNull, reason: 'бир марта ўчгач қайта қуролланмайди');
    });

    test('чегара: бўшдан кейин биринчи келгани янги эмас (бекор/етказилган) — йўқ ва ўчади', () {
      final d = FirstOrderDetector();
      expect(d.onList(const []), isNull);
      expect(d.onList([_o('o1', RestaurantOrderStatus.cancelled)]), isNull);
      expect(d.onList([_placed('o2'), _o('o1', RestaurantOrderStatus.cancelled)]), isNull);
    });

    test('чегара: бўшдан кейин яна бўш — ҳали кутади', () {
      final d = FirstOrderDetector();
      expect(d.onList(const []), isNull);
      expect(d.onList(const []), isNull);
      expect(d.onList([_o('o1', RestaurantOrderStatus.placed)]), 'o1');
    });
  });

  group('MerchantOrdersTab — табрик', () {
    testWidgets('мусбат: буюртмасиз ресторанга биринчи буюртма келди — ойна; «Буюртмани кўриш» ёпади, қабул қилинмайди',
        (t) async {
      final h = await _pumpTab(t);
      expect(find.text('restaurants_m_no_orders'), findsOneWidget);

      h.repo.emit([_placed('o1')]);
      await _settleDialog(t);
      expect(_title, findsOneWidget);
      expect(find.text('restaurants_m_first_order_sub'), findsOneWidget);
      expect(find.text('restaurants_m_first_order_view'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('celebration_confetti')), findsOneWidget);

      await _tapView(t);
      expect(_title, findsNothing);
      expect(h.shown, [1], reason: 'панел Буюртмалар табига ўтади');
      expect(h.repo.acceptCalls, 0, reason: 'авто-қабул йўқ');
      // Буюртма карта ва «Қабул қилиш» тугмаси билан кутиб турибди.
      expect(find.text('restaurants_m_accept'), findsOneWidget);
      await _dispose(t);
    });

    testWidgets('манфий: панел очилганда эски буюртмалар бор — янги буюртма келса ҳам ойна йўқ (овоз/сигнал одатдагидек)',
        (t) async {
      final h = await _pumpTab(t, initial: [_delivered('o0')]);
      h.repo.emit([_placed('o1'), _delivered('o0')]);
      await _settleDialog(t);
      await t.pump(const Duration(seconds: 1));
      expect(_title, findsNothing);
      expect(h.shown, isEmpty);
      await _dispose(t);
    });

    testWidgets('бир марта: ёпилгач кейинги буюртмалар ва панелни қайта очиш — ойна такрорланмайди', (t) async {
      final h = await _pumpTab(t);
      h.repo.emit([_placed('o1')]);
      await _settleDialog(t);
      expect(_title, findsOneWidget);
      await _tapView(t);

      h.repo.emit([_placed('o2'), _placed('o1')]);
      await _settleDialog(t);
      expect(_title, findsNothing);

      // Панел янгидан очилди (масалан эртасига), ресторан ҳали ҳам буюртмасиз кўринган ҳолат — белги бор.
      await _dispose(t);
      final again = await _pumpTab(t);
      again.repo.emit([_placed('o9')]);
      await _settleDialog(t);
      expect(_title, findsNothing);
      await _dispose(t);
    });

    testWidgets('чегара: бошқа ресторан — ўз «биринчи»си алоҳида', (t) async {
      final a = await _pumpTab(t, rid: 'r1');
      a.repo.emit([_placed('o1')]);
      await _settleDialog(t);
      await _tapView(t);
      await _dispose(t);

      final b = await _pumpTab(t, rid: 'r2');
      b.repo.emit([_placed('x1', rid: 'r2')]);
      await _settleDialog(t);
      expect(_title, findsOneWidget);
      await _tapView(t);
      await _dispose(t);
    });

    testWidgets('устида бошқа экран очиқ — ойна кутади, панелга қайтилганда чиқади', (t) async {
      final h = await _pumpTab(t);
      unawaited(_nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('dish form')),
      )));
      await t.pumpAndSettle();

      h.repo.emit([_placed('o1')]);
      await _settleDialog(t);
      await t.pump(const Duration(seconds: 1));
      expect(_title, findsNothing, reason: 'таом формаси устида чиқмайди');

      _nav.currentState!.pop();
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await _settleDialog(t);
      expect(_title, findsOneWidget);
      await _tapView(t);
      expect(h.shown, [1]);
      await _dispose(t);
    });

    testWidgets('устида экран турганда буюртма бошқа жойда қабул қилинди — қайтилганда ойна йўқ', (t) async {
      final h = await _pumpTab(t);
      unawaited(_nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('dish form')),
      )));
      await t.pumpAndSettle();

      h.repo.emit([_placed('o1')]);
      await _settleDialog(t);
      h.repo.emit([_o('o1', RestaurantOrderStatus.accepted)]);
      await _settleDialog(t);

      _nav.currentState!.pop();
      await t.pumpAndSettle();
      await _settleDialog(t);
      expect(_title, findsNothing, reason: '«мижоз кутяпти» энди нотўғри бўларди');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty, reason: 'белги сарфланмади');
      await _dispose(t);
    });
  });

  testWidgets('RestaurantPanelScreen: эга «Меню» табида — табрик чиқади, «Буюртмани кўриш» Буюртмалар табига ўтказади',
      (t) async {
    final repo = _FakeRepo(_r('r1'), initial: const []);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: RestaurantPanelScreen(restaurantId: 'r1', repository: repo, initialTab: 1),
    ));
    await t.pumpAndSettle();
    NavigationBar bar() => t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar().selectedIndex, 1);

    repo.emit([_placed('o1')]);
    await _settleDialog(t);
    expect(_title, findsOneWidget);
    await _tapView(t);
    expect(bar().selectedIndex, 0);
    expect(repo.acceptCalls, 0);
    await _dispose(t);
  });
}
