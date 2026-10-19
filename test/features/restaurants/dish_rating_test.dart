// Таом баҳоси, клиент томони (D-REST-18/32, эга 2026-10-19). Қоида ва ҳисоб — серверда
// (`functions/test/restaurant_dish_ratings_cf.test.js`); бу ерда: агрегатни ўқиш/кўрсатиш,
// буюртмадан баҳоларни ўқиш, баҳолаш карточкаси ва менюдаги ★.

import 'dart:async';
import 'dart:io';

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/dish_stats.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_order_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/dish_rating_card.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

OrderModel _order({
  String restaurantStatus = 'delivered',
  Map<String, int> rated = const {},
  List<OrderItem>? items,
  DateTime? deliveredAt,
}) =>
    OrderModel(
      id: 'o1',
      type: 'restaurant',
      total: 60000,
      status: 'delivered',
      restaurantStatus: restaurantStatus,
      dishRatings: rated,
      // Standart: 1 daqiqa oldin yetkazilgan — baholash muddati ochiq.
      deliveredAt: deliveredAt ?? DateTime.now().subtract(const Duration(minutes: 1)),
      items: items ??
          const [
            OrderItem(itemId: 'osh', name: 'Osh', count: 1),
            OrderItem(itemId: 'somsa', name: 'Somsa', count: 2),
          ],
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('DishStats', () {
    test('o\'rtacha butun sonlardan hisoblanadi; baho yo\'q — 0', () {
      expect(const DishStats(ratingSum: 23, ratingCount: 5).average, closeTo(4.6, 1e-9));
      expect(DishStats.empty.average, 0);
    });

    test('«Yangi» chegarasi: 4 ta baho — yangi, 5 ta — yangi emas (ega: <5)', () {
      expect(const DishStats(ratingSum: 20, ratingCount: 4).isNew, isTrue);
      expect(const DishStats(ratingSum: 25, ratingCount: 5).isNew, isFalse);
      expect(const DishStats(ratingSum: 20, ratingCount: 4).showRating, isFalse);
      expect(const DishStats(ratingSum: 25, ratingCount: 5).showRating, isTrue);
      expect(dishNewRatingCount, 5);
    });

    test('fromMap: null / bo\'sh / eski hujjat — bo\'sh', () {
      expect(DishStats.fromMap(null).ratingCount, 0);
      expect(DishStats.fromMap(const {}).ratingCount, 0);
      expect(DishStats.fromMap(const {'ratingSum': 9}).ratingCount, 0, reason: 'soni yo\'q — baho yo\'q');
    });

    test('fromMap: buzilgan qiymat o\'rtachani 1..5 dan chiqarmaydi', () {
      final hi = DishStats.fromMap(const {'ratingSum': 999, 'ratingCount': 2});
      expect(hi.average, 5);
      final lo = DishStats.fromMap(const {'ratingSum': 0, 'ratingCount': 3});
      expect(lo.average, 1);
      final neg = DishStats.fromMap(const {'ratingSum': -5, 'ratingCount': -2});
      expect(neg.ratingCount, 0);
      final ok = DishStats.fromMap(const {'ratingSum': 12.0, 'ratingCount': 3});
      expect([ok.ratingSum, ok.ratingCount], [12, 3]);
    });
  });

  group('Baholash muddati — 30 daqiqa (ega, 2026-10-19)', () {
    final t0 = DateTime(2026, 10, 19, 12);

    test('dishRatingTimeLeft: 0 → 30:00, 29 → 1:00, 30:00 aniq → 0 qoldi emas (chegara ochiq), 30:01 → yopiq', () {
      expect(dishRatingTimeLeft(t0, t0), const Duration(minutes: 30));
      expect(dishRatingTimeLeft(t0, t0.add(const Duration(minutes: 29))), const Duration(minutes: 1));
      expect(dishRatingTimeLeft(t0, t0.add(const Duration(minutes: 30))), Duration.zero, reason: '30:00 da qolgan vaqt 0');
      expect(dishRatingTimeLeft(t0, t0.add(const Duration(minutes: 30, seconds: 1))), Duration.zero);
      expect(dishRatingTimeLeft(t0, t0.add(const Duration(hours: 5))), Duration.zero);
    });

    test('noma\'lum yetkazilgan vaqt yoki kelajak (soat farqi) — YOPIQ (serverdagi kabi xavfsiz tomon)', () {
      expect(dishRatingTimeLeft(null, t0), Duration.zero);
      expect(dishRatingTimeLeft(t0.add(const Duration(minutes: 1)), t0), Duration.zero);
    });

    test('klient muddati serverdagi RATING_WINDOW_MIN bilan bir xil', () {
      final js = File('functions/restaurant_dish_ratings.js').readAsStringSync();
      final m = RegExp(r'const RATING_WINDOW_MIN = (\d+);').firstMatch(js);
      expect(m, isNotNull, reason: 'functions/restaurant_dish_ratings.js: RATING_WINDOW_MIN yo\'q');
      expect(int.parse(m!.group(1)!), dishRatingWindow.inMinutes);
    });

    Future<void> pump(WidgetTester t, OrderModel o, {required DateTime Function() clock, Future<bool> Function(Map<String, int>)? onSubmit}) async {
      t.view.physicalSize = const Size(390 * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DishRatingCard(order: o, onSubmit: onSubmit ?? (_) async => true, clock: clock),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('qolgan vaqt ko\'rsatiladi; 5 daqiqa va kam — ogohlantirish rangi; ochiq muddatda tugma bor', (t) async {
      final o = _order(deliveredAt: t0);
      await pump(t, o, clock: () => t0.add(const Duration(minutes: 10)));
      expect(find.text(tr('restaurants_rate_left').replaceAll('{min}', '20')), findsOneWidget);
      await pump(t, o, clock: () => t0.add(const Duration(minutes: 27, seconds: 30)));
      expect(find.text(tr('restaurants_rate_left').replaceAll('{min}', '3')), findsOneWidget, reason: '2:30 → yuqoriga yaxlitlanadi');
      expect(find.byKey(const ValueKey('dish-rating-submit')), findsOneWidget);
    });

    testWidgets('muddat tugagan va hech narsa baholanmagan — karta butunlay yo\'q', (t) async {
      await pump(t, _order(deliveredAt: t0), clock: () => t0.add(const Duration(minutes: 31)));
      expect(find.byKey(const ValueKey('dish-rating-card')), findsNothing);
    });

    testWidgets('muddat tugagan, bittasi baholangan — faqat o\'sha (qulflangan), tugma va ko\'rsatma yo\'q', (t) async {
      await pump(t, _order(deliveredAt: t0, rated: const {'osh': 4}), clock: () => t0.add(const Duration(minutes: 45)));
      expect(find.byKey(const ValueKey('dish-rating-card')), findsOneWidget);
      expect(find.text('Osh'), findsOneWidget);
      expect(find.text('Somsa'), findsNothing, reason: 'baholanmagan taom muddatdan keyin ko\'rsatilmaydi');
      expect(find.byKey(const ValueKey('dish-rating-submit')), findsNothing);
      expect(find.byKey(const ValueKey('dish-rating-left')), findsNothing);
      expect(find.text(tr('restaurants_rate_saved')), findsOneWidget);
    });

    testWidgets('ekran ochiq turganda muddat tugasa karta o\'zi yopiladi (taymer)', (t) async {
      var now = t0.add(const Duration(minutes: 29));
      await pump(t, _order(deliveredAt: t0), clock: () => now);
      expect(find.byKey(const ValueKey('dish-rating-submit')), findsOneWidget);
      now = t0.add(const Duration(minutes: 31));
      await t.pump(const Duration(seconds: 21));
      expect(find.byKey(const ValueKey('dish-rating-card')), findsNothing);
    });

    test('OrderModel: deliveredAt yo\'q (eski hujjat) → null → karta ko\'rsatilmaydi', () {
      expect(const OrderModel(id: 'x', type: 'restaurant', total: 1, status: 'delivered', items: []).deliveredAt, isNull);
    });
  });

  group('OrderModel.dishRatings / canRateDishes', () {
    test('parseDishRatings: faqat 1..5 butun; noto\'g\'ri tip/qiymat tashlanadi; yo\'q — bo\'sh', () {
      expect(OrderModel.parseDishRatings(null), isEmpty);
      expect(OrderModel.parseDishRatings('x'), isEmpty);
      expect(
        OrderModel.parseDishRatings({'a': 5, 'b': 1, 'c': 0, 'd': 6, 'e': 4.5, 'f': '3', 'g': 3.0, 7: 5}),
        {'a': 5, 'b': 1, 'g': 3},
      );
    });

    test('canRateDishes: faqat restoran buyurtmasi va FAQAT delivered', () {
      expect(_order().canRateDishes, isTrue);
      for (final s in ['placed', 'accepted', 'ready', 'picked', 'arrived', 'rejected', 'cancelled', 'delivery_failed', '']) {
        expect(_order(restaurantStatus: s).canRateDishes, isFalse, reason: s);
      }
      const bread = OrderModel(id: 'b', type: 'bread', total: 1, status: 'delivered', items: [], restaurantStatus: 'delivered');
      expect(bread.canRateDishes, isFalse);
    });

    test('OrderItem.itemId: eski hujjatda yo\'q — bo\'sh', () {
      expect(OrderItem.fromMap(const {'name': 'Osh', 'price': 1000, 'count': 1}).itemId, '');
      expect(OrderItem.fromMap(const {'itemId': 'osh', 'name': 'Osh'}).itemId, 'osh');
    });
  });

  group('DishRatingCard', () {
    Future<void> pump(
      WidgetTester t, {
      required OrderModel order,
      Future<bool> Function(Map<String, int>)? onSubmit,
      bool busy = false,
      double width = 390,
      double textScale = 1.0,
    }) async {
      t.view.physicalSize = Size(width * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DishRatingCard(order: order, onSubmit: onSubmit ?? (_) async => true, busy: busy),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    Finder star(String id, int n) => find.byKey(ValueKey('dish-star-$id-$n'));
    Finder submit() => find.byKey(const ValueKey('dish-rating-submit'));
    bool enabled(WidgetTester t) => t.widget<FilledButton>(submit()).onPressed != null;
    int filled(WidgetTester t, String id) => [
          for (var n = 1; n <= 5; n++)
            if (t.widget<Icon>(find.descendant(of: star(id, n), matching: find.byType(Icon))).icon == Icons.star_rounded) n,
        ].length;

    testWidgets('boshida tugma o\'chiq va «kamida bitta»; yulduz tanlansa yoqiladi', (t) async {
      await pump(t, order: _order());
      expect(find.text(tr('restaurants_rate_title')), findsOneWidget);
      expect(find.text('Osh'), findsOneWidget);
      expect(find.text('Somsa'), findsOneWidget);
      expect(enabled(t), isFalse);
      expect(find.text(tr('restaurants_rate_pick')), findsOneWidget);
      await t.tap(star('osh', 4));
      await t.pump();
      expect(enabled(t), isTrue);
      expect(filled(t, 'osh'), 4);
      expect(filled(t, 'somsa'), 0);
      expect(find.text(tr('restaurants_rate_pick')), findsNothing);
    });

    testWidgets('yuborish: faqat tanlangan taomlar, to\'g\'ri baholar bilan; muvaffaqiyatda tanlov tozalanadi', (t) async {
      Map<String, int>? sent;
      await pump(t, order: _order(), onSubmit: (s) async {
        sent = s;
        return true;
      });
      await t.tap(star('osh', 5));
      await t.tap(star('osh', 3)); // qayta tanlash — oxirgisi
      await t.pump();
      await t.tap(submit());
      await t.pumpAndSettle();
      expect(sent, {'osh': 3});
      expect(enabled(t), isFalse, reason: 'yuborildi — tanlov tozalandi');
    });

    testWidgets('xato bo\'lsa tanlov SAQLANADI va qayta yuborish mumkin', (t) async {
      var calls = 0;
      await pump(t, order: _order(), onSubmit: (s) async {
        calls += 1;
        return calls > 1;
      });
      await t.tap(star('somsa', 2));
      await t.pump();
      await t.tap(submit());
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(filled(t, 'somsa'), 2, reason: 'xatodan keyin ham tanlov turibdi');
      expect(enabled(t), isTrue);
      await t.tap(submit());
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(enabled(t), isFalse);
    });

    testWidgets('bahosi bor taom QULFLANGAN (bosilmaydi, yuborilmaydi); qolgani baholanadi', (t) async {
      Map<String, int>? sent;
      await pump(t, order: _order(rated: const {'osh': 5}), onSubmit: (s) async {
        sent = s;
        return true;
      });
      expect(filled(t, 'osh'), 5);
      await t.tap(star('osh', 1));
      await t.pump();
      expect(filled(t, 'osh'), 5, reason: 'qulflangan taom o\'zgarmaydi');
      expect(enabled(t), isFalse);
      await t.tap(star('somsa', 5));
      await t.pump();
      await t.tap(submit());
      await t.pumpAndSettle();
      expect(sent, {'somsa': 5}, reason: 'faqat yangi baho yuboriladi');
    });

    testWidgets('hammasi baholangan: tugma va ko\'rsatma yo\'q, sarlavha «Sizning bahoyingiz»', (t) async {
      await pump(t, order: _order(rated: const {'osh': 5, 'somsa': 2}));
      expect(submit(), findsNothing);
      expect(find.text(tr('restaurants_rate_hint')), findsNothing);
      expect(find.text(tr('restaurants_rate_saved')), findsOneWidget);
      expect(filled(t, 'somsa'), 2);
    });

    testWidgets('itemId\'siz (eski) qatorlar va takror itemId e\'tiborsiz; baholanadigani yo\'q — karta yo\'q', (t) async {
      await pump(t, order: _order(items: const [OrderItem(name: 'Eski taom'), OrderItem(itemId: '', name: 'Yana')]));
      expect(find.byKey(const ValueKey('dish-rating-card')), findsNothing);
      await pump(t, order: _order(items: const [OrderItem(itemId: 'osh', name: 'Osh'), OrderItem(itemId: 'osh', name: 'Osh')]));
      expect(star('osh', 1), findsOneWidget, reason: 'takror taom bir marta');
    });

    testWidgets('busy: yulduzlar va tugma bosilmaydi', (t) async {
      await pump(t, order: _order(), busy: true);
      await t.tap(star('osh', 5));
      await t.pump();
      expect(filled(t, 'osh'), 0);
      expect(enabled(t), isFalse);
    });

    testWidgets('yulduz bosish maydoni ≥ 44 va ekran o\'qish ma\'nosi bor', (t) async {
      await pump(t, order: _order());
      final size = t.getSize(star('osh', 3));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(tr('restaurants_rate_star').replaceAll('{n}', '3')), findsWidgets);
    });

    testWidgets('tor ekran 320 va shrift ×2: sinmaydi, besh yulduz bir qatorda sig\'adi', (t) async {
      await pump(t, order: _order(), width: 320, textScale: 2.0);
      expect(t.takeException(), isNull);
      final first = t.getRect(star('osh', 1));
      final last = t.getRect(star('osh', 5));
      expect(last.right, lessThanOrEqualTo(320));
      expect(first.top, last.top, reason: 'bir qatorda');
    });
  });

  group('RestaurantOrderScreen: baholash', () {
    Future<_OrderRepo> pumpOrder(WidgetTester t, OrderModel order, {Object? failWith}) async {
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final repo = _OrderRepo(order, failWith: failWith);
      await t.pumpWidget(l10nApp(home: RestaurantOrderScreen(orderId: 'o1', repository: repo)));
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('yetkazilgan buyurtma: karta bor, tanlanganlar callable\'ga ketadi, «rahmat» xabari', (t) async {
      final repo = await pumpOrder(t, _order());
      expect(find.byKey(const ValueKey('dish-rating-card')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dish-star-osh-5')));
      await t.tap(find.byKey(const ValueKey('dish-star-somsa-2')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('dish-rating-submit')));
      await t.pumpAndSettle();
      expect(repo.submitted, [
        {'osh': 5, 'somsa': 2},
      ]);
      expect(find.text(tr('restaurants_rate_done')), findsOneWidget);
    });

    testWidgets('server xatosi (ORDER_NOT_DELIVERED): xabar chiqadi, tanlov saqlanadi, qayta yuborish mumkin', (t) async {
      final repo = await pumpOrder(
        t,
        _order(),
        failWith: const RestaurantsException('failed-precondition', 'ORDER_NOT_DELIVERED', 'x'),
      );
      await t.tap(find.byKey(const ValueKey('dish-star-osh-4')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('dish-rating-submit')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_err_ORDER_NOT_DELIVERED')), findsOneWidget);
      expect(repo.submitted, hasLength(1));
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('dish-rating-submit'))).onPressed, isNotNull);
    });

    testWidgets('yetkazilMAGAN buyurtmada (accepted) baholash kartasi YO\'Q', (t) async {
      await pumpOrder(t, _order(restaurantStatus: 'accepted'));
      expect(find.byKey(const ValueKey('dish-rating-card')), findsNothing);
    });
  });

  group('RestaurantScreen: taom bahosi ★', () {
    Future<void> pumpMenu(WidgetTester t, Map<String, DishStats> stats, {double width = 390, double textScale = 1.0}) async {
      t.view.physicalSize = Size(width * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      const r = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: RestaurantScreen(
          restaurant: r,
          repository: _MenuRepo(),
          cart: RestaurantCart(),
          itemClipsLoader: (_) async => const {}, restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => stats,
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('5 va undan ko\'p baho — ★ o\'rtacha (soni); 4 va undan kam — ko\'rsatilmaydi', (t) async {
      await pumpMenu(t, {
        'osh': const DishStats(ratingSum: 47, ratingCount: 10),
        'somsa': const DishStats(ratingSum: 20, ratingCount: 4),
        'lagmon': const DishStats(ratingSum: 25, ratingCount: 5),
      });
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('dish-rating-osh')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('dish-rating-osh'))) as Text).data, '4.7 (10)');
      expect(find.byKey(const ValueKey('dish-rating-somsa')), findsNothing);
      expect((t.widget(find.byKey(const ValueKey('dish-rating-lagmon'))) as Text).data, '5.0 (5)');
    });

    testWidgets('statistika yuklanmasa (xato) menyu baholarsiz ishlayveradi', (t) async {
      const r = Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved');
      await t.pumpWidget(l10nApp(
        home: RestaurantScreen(
          restaurant: r,
          repository: _MenuRepo(),
          cart: RestaurantCart(),
          itemClipsLoader: (_) async => const {}, restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => throw StateError('offline'),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Osh'), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-rating-osh')), findsNothing);
    });

    testWidgets('tor ekran 320 + shrift ×2: nom + narx + ★ qotirilgan qator balandligiga sig\'adi (overflow yo\'q)', (t) async {
      await pumpMenu(t, {'osh': const DishStats(ratingSum: 47, ratingCount: 10)}, width: 320, textScale: 2.0);
      expect(t.takeException(), isNull);
    });
  });
}

class _OrderRepo implements RestaurantsRepository {
  _OrderRepo(this.order, {this.failWith});

  final OrderModel order;
  final Object? failWith;
  final submitted = <Map<String, int>>[];

  @override
  Stream<OrderModel?> watchOrder(String id) => Stream.value(order);

  @override
  Future<Restaurant?> getRestaurant(String id) async => null;

  @override
  Future<List<String>> submitDishRatings(String orderId, Map<String, int> stars) async {
    submitted.add(Map.of(stars));
    final err = failWith;
    if (err != null) throw err;
    return stars.keys.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _MenuRepo implements RestaurantsRepository {
  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(const Restaurant(id: 'r1', name: 'Gurlan osh', status: 'approved'));

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) =>
      Stream.value(const [MenuCategory(id: 'c1', name: 'Asosiy', sort: 1)]);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value(const [
        MenuItem(id: 'osh', name: 'Osh', price: 40000, categoryId: 'c1', sort: 1),
        MenuItem(id: 'somsa', name: 'Somsa', price: 10000, categoryId: 'c1', sort: 2),
        MenuItem(id: 'lagmon', name: 'Lag\'mon', price: 35000, categoryId: 'c1', sort: 3),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
