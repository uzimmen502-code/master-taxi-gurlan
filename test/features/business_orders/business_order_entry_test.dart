import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_orders/data/business_order_session.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/widgets/business_order_entry.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'business_order_domain_test.dart' show item;
import 'fake_business_orders_repository.dart';

Business _biz({BusinessCategory c = BusinessCategory.retail, bool online = false, String status = 'active'}) => Business(
      id: 'b1',
      ownerId: '998901111111',
      name: 'Дўкон',
      category: c,
      phone: '998901111111',
      lat: online ? 0 : 41.5,
      lng: online ? 0 : 60.3,
      online: online,
      status: status,
    );

final _cta = find.byKey(const ValueKey('biz_order_cta'));

Future<({FakeBusinessOrdersRepository repo, BusinessCartStore store, List<BusinessCart> opened})> _pump(
  WidgetTester tester, {
  TvShopItem? it,
  Business? business,
  BusinessOrdersAccess access = const BusinessOrdersAccess(allowed: true, stage: 'public'),
  String me = '998902222222',
}) async {
  tester.view.physicalSize = const Size(420 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeBusinessOrdersRepository()..accessResult = access;
  final store = BusinessCartStore();
  final opened = <BusinessCart>[];
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(), // қайта чақирилганда — тоза ҳолат
    theme: AppTheme.light,
    home: Scaffold(
      body: ListView(children: [
        BusinessOrderEntry(
          item: it ?? item('a'),
          myUid: me,
          repository: repo,
          store: store,
          accessCache: BusinessOrdersAccessCache(),
          loadBusiness: (id) async => business ?? _biz(),
          openCheckout: (ctx, cart) async => opened.add(cart),
        ),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
  return (repo: repo, store: store, opened: opened);
}

void main() {
  group('дарвоза: тугма фақат ҳаммаси мос бўлса', () {
    testWidgets('очиқ дарвоза + харитадаги дўкон + маҳсулот → «Буюртма бериш»', (tester) async {
      final r = await _pump(tester);
      expect(_cta, findsOneWidget);
      expect(r.repo.calls, contains('access:b1'), reason: 'дарвоза объект бўйича сўралади (пилот тумани)');
    });

    for (final reason in ['MODULE_OFF', 'MODULE_INTERNAL_ONLY', 'MODULE_NOT_IN_PILOT']) {
      testWidgets('ёпиқ дарвоза ($reason) → тугма йўқ', (tester) async {
        await _pump(tester, access: BusinessOrdersAccess(allowed: false, stage: 'off', reason: reason));
        expect(_cta, findsNothing);
      });
    }

    testWidgets('хизмат / келишиладиган нарх / ўз маҳсулоти → тугма йўқ, сервер чақирилмайди', (tester) async {
      var r = await _pump(tester, it: item('a', kind: 'service'));
      expect(_cta, findsNothing);
      expect(r.repo.calls, isEmpty);
      r = await _pump(tester, it: item('a', unit: PriceUnit.negotiable));
      expect(_cta, findsNothing);
      r = await _pump(tester, me: '998901111111');
      expect(_cta, findsNothing);
      expect(r.repo.calls, isEmpty);
    });

    testWidgets('онлайн объект / блокланган / курьерсиз тур (овқатланиш, тиббиёт) → тугма йўқ', (tester) async {
      await _pump(tester, business: _biz(online: true));
      expect(_cta, findsNothing);
      await _pump(tester, business: _biz(status: 'blocked'));
      expect(_cta, findsNothing);
      await _pump(tester, business: _biz(c: BusinessCategory.food));
      expect(_cta, findsNothing);
      await _pump(tester, business: _biz(c: BusinessCategory.health));
      expect(_cta, findsNothing);
    });
  });

  testWidgets('миқдор танлаш → «Расмийлаштириш»: саватда шу миқдор, варақ очилади', (tester) async {
    final r = await _pump(tester, it: item('a', unit: PriceUnit.kg));
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    expect(find.text('3 price_unit_short_kg'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('biz_add_plus')));
    await tester.tap(find.byKey(const ValueKey('biz_add_plus')));
    await tester.pumpAndSettle();
    expect(find.text('3 price_unit_short_kg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biz_add_checkout')));
    await tester.pumpAndSettle();
    expect(r.opened.single.qtyOf('a'), 3);
    expect(r.opened.single.businessName, 'Дўкон');
  });

  testWidgets('«Саватга қўшиш» → сават қатори пайдо бўлади', (tester) async {
    final r = await _pump(tester);
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biz_add_to_cart')));
    await tester.pumpAndSettle();
    expect(r.store.existing('b1')!.qtyOf('a'), 1);
    expect(find.byKey(const ValueKey('biz_order_cart_bar')), findsOneWidget);
    expect(r.opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('biz_order_cart_bar')));
    await tester.pumpAndSettle();
    expect(r.opened, hasLength(1));
  });
}
