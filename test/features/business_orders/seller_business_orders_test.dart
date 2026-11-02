import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_next_step_screen.dart';
import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/screens/seller_business_orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_business_orders_repository.dart';

BusinessOrder _o(String id, String status, {String businessId = 'b1', int itemsTotal = 12000}) => BusinessOrder(
      id: id,
      status: status,
      businessId: businessId,
      businessName: 'Дўкон $businessId',
      itemsTotal: itemsTotal,
      deliveryFee: 8000,
      total: itemsTotal + 8000,
      userName: 'Вали',
      createdAt: DateTime(2026, 11, 3, 12),
      items: const [],
    );

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('сотувчи рўйхати', () {
    testWidgets('сўров ўз телефони бўйича; фаол/тарих фильтри; объект бўйича фильтр', (tester) async {
      _view(tester);
      final repo = FakeBusinessOrdersRepository();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: SellerBusinessOrdersScreen(
          sellerUid: '+998 90 111 11 11',
          businessId: 'b1',
          repository: repo,
          showDeliveryFailedDecisions: false,
        ),
      ));
      await tester.pump();
      expect(repo.calls, contains('watchSeller:998901111111'));
      repo.sellerOrders.add([
        _o('p1', 'placed'),
        _o('r1', 'ready'),
        _o('d1', 'delivered'),
        _o('x1', 'placed', businessId: 'b2'),
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biz_seller_order_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_seller_order_r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_seller_order_d1')), findsNothing);
      expect(find.byKey(const ValueKey('biz_seller_order_x1')), findsNothing, reason: 'бошқа объект');
      expect(find.text('biz_order_new_badge'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('biz_seller_filter_history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biz_seller_order_d1')), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_seller_order_p1')), findsNothing);
    });

    test('сўров шакли rules билан бир хил (sellerUid ==, createdAt desc)', () {
      final s = BusinessOrdersRepository.sellerQuerySpec('998901111111');
      expect((s.field, s.orderBy, s.descending), ('sellerUid', 'createdAt', true));
    });
  });

  group('сотувчи тафсилоти', () {
    Future<FakeBusinessOrdersRepository> open(WidgetTester tester, BusinessOrder o) async {
      _view(tester);
      final repo = FakeBusinessOrdersRepository()..codes[o.id] = '4821';
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: SellerBusinessOrderDetailScreen(orderId: o.id, repository: repo),
      ));
      await tester.pump();
      repo.orderCtrl(o.id).add(o);
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('placed: «Қабул қилиш» → businessAcceptOrder', (tester) async {
      final repo = await open(tester, _o('p1', 'placed'));
      expect(find.byKey(const ValueKey('biz_seller_ready')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('biz_seller_accept')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('accept:p1'));
      expect(find.text('biz_order_accepted_ok'), findsOneWidget);
    });

    testWidgets('рад этиш — сабаб билан', (tester) async {
      final repo = await open(tester, _o('p1', 'placed'));
      await tester.tap(find.byKey(const ValueKey('biz_seller_reject')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('biz_seller_reject_reason')), 'Тугаган');
      await tester.tap(find.byKey(const ValueKey('biz_seller_reject_confirm')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('reject:p1:Тугаган'));
    });

    testWidgets('accepted: «Тайёр» → businessMarkReady; хато — дўстона матн', (tester) async {
      final repo = await open(tester, _o('a1', 'accepted'));
      repo.nextActionError = const BusinessOrderException('failed-precondition', 'ORDER_INVALID_TRANSITION');
      await tester.tap(find.byKey(const ValueKey('biz_seller_ready')));
      await tester.pumpAndSettle();
      expect(find.text('biz_order_err_order_invalid_transition'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_seller_ready')));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c == 'ready:a1'), hasLength(2));
    });

    testWidgets('ready: олиб кетиш коди кўрсатилади (accepted да — йўқ)', (tester) async {
      await open(tester, _o('r1', 'ready'));
      expect(find.byKey(const ValueKey('biz_seller_pickup_code')), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
    });

    testWidgets('accepted: код ҳали кўрсатилмайди', (tester) async {
      await open(tester, _o('a1', 'accepted'));
      expect(find.byKey(const ValueKey('biz_seller_pickup_code')), findsNothing);
    });
  });

  group('эга хабидаги «Буюртмалар» қатори', () {
    Business b() => const Business(
          id: 'b1',
          ownerId: '998901111111',
          name: 'Дўкон',
          category: BusinessCategory.retail,
          phone: '998901111111',
          lat: 41.5,
          lng: 60.3,
        );

    Future<List<String>> pump(WidgetTester tester, BizSellerOrdersInfo? info) async {
      _view(tester);
      final log = <String>[];
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.light,
        home: BusinessNextStepScreen(
          business: b(),
          loadOfferCount: (_) async => 1,
          loadOrdersInfo: (_) async => info,
          openOrders: (ctx, x) async => log.add('orders:${x.id}'),
        ),
      ));
      await tester.pumpAndSettle();
      return log;
    }

    testWidgets('маълумот йўқ (дарвоза ёпиқ) — қатор йўқ', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const ValueKey('biz_next_step_orders')), findsNothing);
    });

    testWidgets('янги буюртмалар сони кўринади, босилса — буюртмалар экрани', (tester) async {
      final log = await pump(tester, (newCount: 2, total: 5));
      expect(find.byKey(const ValueKey('biz_next_step_orders')), findsOneWidget);
      expect(find.text('biz_order_seller_entry_sub'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('biz_next_cta_orders')), 100);
      await tester.tap(find.byKey(const ValueKey('biz_next_cta_orders')));
      await tester.pumpAndSettle();
      expect(log, ['orders:b1']);
    });

    test('онлайн объектда маълумот сўралмайди', () async {
      const online = Business(
        id: 'b2',
        ownerId: '998901111111',
        name: 'Онлайн',
        category: BusinessCategory.retail,
        phone: '998901111111',
        lat: 0,
        lng: 0,
        online: true,
      );
      final repo = FakeBusinessOrdersRepository();
      expect(await loadBizSellerOrdersInfo(online, repository: repo), isNull);
      expect(repo.calls, isEmpty);
    });

    test('дарвоза очиқ, буюртма йўқ → қатор (0 та); ёпиқ, буюртма йўқ → йўқ', () async {
      final repo = FakeBusinessOrdersRepository();
      expect(await loadBizSellerOrdersInfo(b(), repository: repo), (newCount: 0, total: 0));
      repo.accessResult = const BusinessOrdersAccess(allowed: false, stage: 'off', reason: 'MODULE_OFF');
      expect(await loadBizSellerOrdersInfo(b(), repository: repo), isNull);
    });
  });
}
