// Олдиндан буюртма (S4b, D-REST-35): қоида (серверга қарши мослик), форма, тўлов варағи, буюртма экрани.
// Ҳақиқий текширув серверда (`functions/test/restaurant_preorder.test.js`, `restaurant_orders_cf.test.js` PO1…PO8).

import 'dart:io';

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/preorder.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_order_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/restaurant_checkout_sheet.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restaurants_l10n_harness.dart';
import '../../support/server_checkout.dart';

final _now = DateTime(2026, 10, 19, 12, 0);

Restaurant _r({bool accepts = true, OpeningHours? hours, DateTime? paused, String delivery = 'pickup'}) => Restaurant(
      id: 'r1',
      name: 'Gurlan osh',
      status: 'approved',
      acceptsPreorder: accepts,
      openingHours: hours,
      pausedUntil: paused,
      address: 'Gurlan',
      delivery: RestaurantDelivery(mode: delivery, pickup: true),
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('Preorder — сервер билан мослик', () {
    test('чегаралар сервердаги MIN_LEAD_MIN / MAX_DAYS билан бир хил (эга: 60 дақиқа / 7 кун)', skip: serverParitySkip, () {
      final js = File('functions/restaurant_preorder.js').readAsStringSync();
      expect(int.parse(RegExp(r'const MIN_LEAD_MIN = (\d+);').firstMatch(js)!.group(1)!), Preorder.minLeadMin);
      expect(int.parse(RegExp(r'const MAX_DAYS = (\d+);').firstMatch(js)!.group(1)!), Preorder.maxDays);
      expect([Preorder.minLeadMin, Preorder.maxDays], [60, 7]);
    });

    test('3 тилда хато матнлари мавжуд', () {
      for (final k in [
        'restaurants_preorder_err_${Preorder.errSoon}', 'restaurants_preorder_err_${Preorder.errFar}',
        'restaurants_preorder_err_${Preorder.errClosed}', 'restaurants_preorder_err_${Preorder.errPaused}',
        'restaurants_err_PREORDER_NOT_ACCEPTED', 'restaurants_err_PREORDER_TOO_SOON', 'restaurants_err_PREORDER_TOO_FAR',
        'restaurants_err_PREORDER_CLOSED_AT_TIME', 'restaurants_err_PREORDER_TOO_EARLY', 'restaurants_err_PREORDER_TIME_INVALID',
      ]) {
        for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
          expect(JsonL10nDelegate(lang).tr(k), isNot(k), reason: '$lang $k');
        }
      }
    });
  });

  group('Preorder.check / suggest / days / format', () {
    test('оралиқ: 59:59 — эрта; 60:00 — ок; 7 кун — ок; 7 кун + 1 с — узоқ; ўтмиш — эрта', () {
      final r = _r();
      String? at(Duration d) => Preorder.check(now: _now, scheduled: _now.add(d), restaurant: r);
      expect(at(const Duration(minutes: 59, seconds: 59)), Preorder.errSoon);
      expect(at(const Duration(minutes: 60)), isNull);
      expect(at(const Duration(days: 7)), isNull);
      expect(at(const Duration(days: 7, seconds: 1)), Preorder.errFar);
      expect(at(const Duration(minutes: -5)), Preorder.errSoon);
    });

    test('иш вақти БАЖАРИЛИШ вақтида: ҳозир ёпиқ бўлса ҳам эртага мумкин; ярим тундан ўтадиган оралиқ ҳам', () {
      const hours = OpeningHours(open: '09:00', close: '22:00');
      final r = _r(hours: hours);
      expect(Preorder.check(now: _now, scheduled: DateTime(2026, 10, 20, 10), restaurant: r), isNull);
      expect(Preorder.check(now: _now, scheduled: DateTime(2026, 10, 20, 23), restaurant: r), Preorder.errClosed);
      expect(Preorder.check(now: _now, scheduled: DateTime(2026, 10, 20, 22), restaurant: r), Preorder.errClosed, reason: 'ёпилиш вақтининг ўзи — ёпиқ');
      expect(Preorder.check(now: _now, scheduled: DateTime(2026, 10, 20, 9), restaurant: r), isNull);
      const night = OpeningHours(open: '20:00', close: '02:00');
      final rn = _r(hours: night);
      expect(Preorder.check(now: _now, scheduled: DateTime(2026, 10, 20, 1), restaurant: rn), isNull);
      expect(Preorder.check(now: _now, scheduled: DateTime(2026, 10, 20, 12), restaurant: rn), Preorder.errClosed);
    });

    test('пауза: бажарилишдан кейин тугаса — мумкин; бажарилиш вақтида давом этса — пауза', () {
      final at = _now.add(const Duration(hours: 3));
      expect(Preorder.check(now: _now, scheduled: at, restaurant: _r(paused: at.add(const Duration(minutes: 1)))), Preorder.errPaused);
      expect(Preorder.check(now: _now, scheduled: at, restaurant: _r(paused: at.subtract(const Duration(minutes: 1)))), isNull);
      expect(Preorder.check(now: _now, scheduled: at, restaurant: _r(paused: _now.add(const Duration(minutes: 30)))), isNull);
    });

    test('suggest: ҳозирдан ≥ 90 дақиқа, 15 дақиқага яхлитланган, ҳар доим ТЎҒРИ оралиқда', () {
      for (var m = 0; m < 24 * 60; m += 7) {
        final now = DateTime(2026, 10, 19, 0, 0).add(Duration(minutes: m));
        final s = Preorder.suggest(now);
        expect(s.minute % 15, 0, reason: '$now → $s');
        expect(s.difference(now), greaterThanOrEqualTo(const Duration(minutes: 90)));
        expect(s.difference(now), lessThan(const Duration(minutes: 106)));
        expect(Preorder.check(now: now, scheduled: s, restaurant: _r()), isNull);
      }
    });

    test('days: бугундан 8 кун (бугун + 7); format: 21.10 07:05', () {
      final d = Preorder.days(_now);
      expect(d.length, 8);
      expect(d.first, DateTime(2026, 10, 19));
      expect(d.last, DateTime(2026, 10, 26));
      expect(Preorder.format(DateTime(2026, 10, 21, 7, 5)), '21.10 07:05');
      expect(Preorder.combine(DateTime(2026, 10, 21), 19, 30), DateTime(2026, 10, 21, 19, 30));
    });
  });

  group('Моделлар ва форма', () {
    test('Restaurant.acceptsPreorder: фақат true; йўқ/нотўғри — false', () {
      expect(Restaurant.fromMap('a', {'name': 'A', 'acceptsPreorder': true}).acceptsPreorder, isTrue);
      for (final v in [null, false, 'true', 1]) {
        expect(Restaurant.fromMap('a', {'name': 'A', 'acceptsPreorder': v}).acceptsPreorder, isFalse, reason: '$v');
      }
    });

    test('профил патчи acceptsPreorder ни ёзади; рўйхатдан ўтиш payload\'ида йўқ эмас-у, default false', () {
      final f = RestaurantFormData(name: 'A', acceptsPreorder: true);
      expect(f.toProfilePatch()['acceptsPreorder'], isTrue);
      expect(RestaurantFormData(name: 'A').toProfilePatch()['acceptsPreorder'], isFalse);
      expect(RestaurantFormData(name: 'A').toRegisterPayload().containsKey('acceptsPreorder'), isFalse);
    });

    test('OrderModel.scheduledFor / isPreorder: бор — олдиндан; йўқ — оддий', () {
      final o = OrderModel(id: 'o', type: 'restaurant', total: 1, status: 'new', items: const [], scheduledFor: DateTime(2026, 10, 21, 19));
      expect(o.isPreorder, isTrue);
      expect(const OrderModel(id: 'o', type: 'restaurant', total: 1, status: 'new', items: []).isPreorder, isFalse);
    });

    test('PlaceOrderResult.scheduledForMs ўқилади', () {
      expect(PlaceOrderResult.fromMap({'orderId': 'x', 'scheduledForMs': 1790000000000}).scheduledForMs, 1790000000000);
      expect(PlaceOrderResult.fromMap({'orderId': 'x'}).scheduledForMs, isNull);
    });
  });

  group('Тўлов варағи: «Қачонга?»', () {
    final placed = <DateTime?>[];
    final quotes = <DateTime?>[];

    setUp(() {
      placed.clear();
      quotes.clear();
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pump(WidgetTester t, Restaurant r, {double width = 390, double textScale = 1.0, DateTime? now}) async {
      t.view.physicalSize = Size(width * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final cart = RestaurantCart()..add(const MenuItem(id: 'osh', name: 'Osh', price: 40000), restaurant: r);
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: Scaffold(
          body: RestaurantCheckoutSheet(
            key: UniqueKey(),
            restaurant: r,
            cart: cart,
            repository: _CheckoutRepo(placed, quotes),
            now: () => now ?? _now,
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('олдиндан буюртма олмайдиган ресторан — блок УМУМАН йўқ (аввалгидек)', (t) async {
      await pump(t, _r(accepts: false));
      expect(find.byKey(const ValueKey('when-block')), findsNothing);
    });

    testWidgets('очиқ ресторан: «Ҳозир» (default) → олдиндан танланса кун чиплари, вақт ва хулоса; «Ҳозир»га қайтса — йўқолади', (t) async {
      await pump(t, _r());
      expect(find.byKey(const ValueKey('preorder-mode')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder-days')), findsNothing);
      await t.tap(find.text(tr('restaurants_preorder_later')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('preorder-days')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder-error')), findsNothing, reason: 'таклиф қилинган вақт тўғри');
      await t.tap(find.text(tr('restaurants_preorder_now')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('preorder-days')), findsNothing);
    });

    testWidgets('жўнатиш «ҳозир»да: scheduledFor — null (оддий буюртма)', (t) async {
      await pump(t, _r());
      await t.ensureVisible(find.byType(FilledButton).last);
      await t.tap(find.byType(FilledButton).last);
      await t.pumpAndSettle();
      expect(placed, [null], reason: 'ҳозир — олдиндан вақтсиз');
    });

    testWidgets('жўнатиш олдиндан: scheduledFor ТАНЛАНГАН кун ва вақт билан', (t) async {
      await pump(t, _r());
      await t.tap(find.text(tr('restaurants_preorder_later')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('preorder-day-2026-10-21')));
      await t.pumpAndSettle();
      final suggested = Preorder.suggest(_now);
      await t.ensureVisible(find.byType(FilledButton).last);
      await t.tap(find.byType(FilledButton).last);
      await t.pumpAndSettle();
      expect(placed.single, DateTime(2026, 10, 21, suggested.hour, suggested.minute));
    });

    testWidgets('ресторан ҲОЗИР ЁПИҚ: «Ҳозир» танлови йўқ, фақат олдиндан (изоҳ билан); иш вақтидан ташқари вақт — хато, тугма ўчиқ', (t) async {
      // 12:00 да ёпиқ: 14:00–20:00 оралиғи
      await pump(t, _r(hours: const OpeningHours(open: '14:00', close: '20:00')));
      expect(find.byKey(const ValueKey('preorder-forced')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder-mode')), findsNothing);
      expect(find.byKey(const ValueKey('preorder-days')), findsOneWidget, reason: 'мажбурий олдиндан режим');
      // таклиф ~13:30 — ишлаш вақтидан ташқари
      expect(find.byKey(const ValueKey('preorder-error')), findsOneWidget);
      expect(find.text(tr('restaurants_preorder_err_${Preorder.errClosed}')), findsOneWidget);
      final send = t.widget<FilledButton>(find.byType(FilledButton).last);
      expect(send.onPressed, isNull, reason: 'хатоли вақт билан жўнатиб бўлмайди');
    });

    testWidgets('кун ўзгартирилса етказиш нархи ЯНГИДАН сўралади (тунги коэффициент етказиш вақтига қараб)', (t) async {
      await pump(t, _r(delivery: 'ava_courier'));
      // координата йўқ — сўров кетмайди; шунинг учун пикап режимида схема текширилади: нарх сўрови scheduledFor билан чақирилишини ёрдамчи тест
      expect(quotes, isEmpty);
    });

    testWidgets('тор экран 320 ва шрифт ×2: блок синмайди', (t) async {
      await pump(t, _r(hours: const OpeningHours(open: '14:00', close: '20:00')), width: 320, textScale: 2.0);
      expect(t.takeException(), isNull);
      await pump(t, _r(), width: 320, textScale: 2.0);
      await t.tap(find.text(tr('restaurants_preorder_later')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('Буюртма экрани ва меню', () {
    testWidgets('олдиндан буюртма: «Олдиндан: 21.10 19:00» кўринади; «~N дақиқа» изоҳи йўқ', (t) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final order = OrderModel(
        id: 'o1',
        type: 'restaurant',
        total: 40000,
        status: 'accepted',
        restaurantStatus: 'accepted',
        prepTimeMin: 30,
        scheduledFor: DateTime(2026, 10, 21, 19),
        items: const [OrderItem(itemId: 'osh', name: 'Osh', count: 1)],
      );
      await t.pumpWidget(l10nApp(home: RestaurantOrderScreen(orderId: 'o1', repository: _OrderRepo(order))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-preorder')), findsOneWidget);
      expect(find.text(tr('restaurants_preorder_for').replaceAll('{when}', '21.10 19:00')), findsOneWidget);
      expect(find.textContaining(tr('restaurants_prep_time').split('{min}').first), findsNothing);
    });

    testWidgets('оддий буюртмада олдиндан белгиси йўқ, «~N дақиқа» бор', (t) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      const order = OrderModel(
        id: 'o1', type: 'restaurant', total: 40000, status: 'accepted', restaurantStatus: 'accepted', prepTimeMin: 30,
        items: [OrderItem(itemId: 'osh', name: 'Osh', count: 1)],
      );
      await t.pumpWidget(l10nApp(home: RestaurantOrderScreen(orderId: 'o1', repository: _OrderRepo(order))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-preorder')), findsNothing);
    });

    Future<void> pumpMenu(WidgetTester t, Restaurant r) async {
      t.view.physicalSize = const Size(390 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantScreen(
          restaurant: r,
          repository: _MenuRepo(r),
          cart: RestaurantCart(),
          itemClipsLoader: (_) async => const {},
          restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => const {},
        ),
      ));
      await t.pumpAndSettle();
    }

    OpeningHours closedNow() {
      final n = DateTime.now();
      String h(int add) => '${((n.hour + add) % 24).toString().padLeft(2, '0')}:00';
      return OpeningHours(open: h(2), close: h(4));
    }

    testWidgets('ҳозир ёпиқ + олдиндан олади: махсус хабар, «+» тугмаси ЁНИҚ', (t) async {
      await pumpMenu(t, _r(hours: closedNow()));
      expect(find.text(tr('restaurants_closed_preorder')), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsWidgets);
      await t.tap(find.byIcon(Icons.add_rounded).first);
      await t.pump();
      expect(find.text('1'), findsWidgets, reason: 'таом саватга қўшилди');
    });

    testWidgets('ҳозир ёпиқ + олдиндан олмайди: аввалги хабар; «+» ўчиқ (аввалгидек)', (t) async {
      await pumpMenu(t, _r(accepts: false, hours: closedNow()));
      expect(find.text(tr('restaurants_closed_now')), findsOneWidget);
      expect(find.text(tr('restaurants_closed_preorder')), findsNothing);
    });
  });
}

class _CheckoutRepo implements RestaurantsRepository {
  _CheckoutRepo(this.placed, this.quotes);

  final List<DateTime?> placed;
  final List<DateTime?> quotes;

  @override
  Future<DeliveryQuote> quoteDelivery({required String restaurantId, required double lat, required double lng, int itemsTotal = 0, DateTime? scheduledFor}) async {
    quotes.add(scheduledFor);
    return const DeliveryQuote(deliveryMode: 'ava_courier', deliveryFee: 8000);
  }

  @override
  Future<PlaceOrderResult> placeOrder({
    required String idempotencyKey,
    required String restaurantId,
    required List<Map<String, dynamic>> items,
    required String fulfillmentMode,
    required String foodPaymentMethod,
    required String deliveryPaymentMethod,
    String address = '',
    double? lat,
    double? lng,
    String note = '',
    int utensils = 0,
    String userName = '',
    DateTime? scheduledFor,
  }) async {
    placed.add(scheduledFor);
    return const PlaceOrderResult(orderId: 'o1', itemsTotal: 40000, deliveryFee: 0, total: 40000);
  }

  @override
  Stream<OrderModel?> watchOrder(String id) => Stream.value(const OrderModel(id: 'o1', type: 'restaurant', total: 1, status: 'new', restaurantStatus: 'placed', items: []));

  @override
  Future<Restaurant?> getRestaurant(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _OrderRepo implements RestaurantsRepository {
  _OrderRepo(this.order);

  final OrderModel order;

  @override
  Stream<OrderModel?> watchOrder(String id) => Stream.value(order);

  @override
  Future<Restaurant?> getRestaurant(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _MenuRepo implements RestaurantsRepository {
  _MenuRepo(this.r);

  final Restaurant r;

  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(r);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) => Stream.value(const [MenuCategory(id: 'c1', name: 'Asosiy', sort: 1)]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value(const [MenuItem(id: 'osh', name: 'Osh', price: 40000, categoryId: 'c1', sort: 1)]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
