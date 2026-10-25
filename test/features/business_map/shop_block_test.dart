import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/admin_web/screens/business_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/screens/business_products_admin_dialog.dart';
import 'package:ava_gurlan/features/admin_web/screens/shop_admin_screen.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_products_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_item_detail_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга қарори 2026-10-25: админ назорати барча кириш йўлларида — дўкон/йўналиш/маҳсулот блоки.
const _owner = '998901111111';

class _FakeRepo extends BusinessRepository {
  _FakeRepo({this.mine = const []});

  List<Business> mine;
  final calls = <String>[];
  Object? failWith;

  @override
  Future<List<Business>> fetchRecent({int limit = 200}) async => mine;

  @override
  Future<List<Business>> fetchByOwner(String ownerId) async {
    calls.add('byOwner:$ownerId');
    return mine;
  }

  @override
  Future<int> adminSetStatus(String businessId, {required String status, required String reason}) async {
    calls.add('biz:$businessId:$status:$reason');
    if (failWith != null) throw failWith!;
    return 2;
  }

  @override
  Future<void> adminSetShopStatus(String ownerPhone, {required String status, required String reason}) async {
    calls.add('shop:$ownerPhone:$status:$reason');
    if (failWith != null) throw failWith!;
  }
}

class _FakeShop implements TvShopRepository {
  _FakeShop({this.shop, this.items = const [], this.recent = const []});

  TvShop? shop;
  List<TvShopItem> items;
  List<TvShopItem> recent;
  final calls = <String>[];

  @override
  Future<TvShop?> fetchShop(String ownerPhone) async {
    calls.add('shop:$ownerPhone');
    return shop;
  }

  @override
  Future<List<TvShopItem>> fetchRecentAll({int limit = 100}) async => recent;

  @override
  Future<List<TvShopItem>> fetchOwnShopItems(String ownerPhone, {bool onlyActive = false}) async {
    calls.add('own:$ownerPhone:$onlyActive');
    return TvShopRepository.visibleOwnShopItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  @override
  Future<List<TvShopItem>> fetchByBusiness(String businessId, {String ownerPhone = '', bool onlyActive = true, int limit = 200}) async {
    calls.add('biz:$businessId');
    return TvShopRepository.visibleBusinessItems(items.where((i) => i.businessId == businessId), ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Business _biz(String id, String name, {String status = 'active'}) => Business(
      id: id,
      ownerId: _owner,
      name: name,
      category: BusinessCategory.retail,
      phone: '998901234567',
      lat: 41.3,
      lng: 69.2,
      status: status,
    );

TvShopItem _item(String id, String title, {String status = 'active', String businessId = '', String photo = ''}) => TvShopItem(
      id: id,
      ownerPhone: _owner,
      ownerName: 'x',
      title: title,
      price: 5000,
      photoUrl: photo,
      photoUrls: photo.isEmpty ? const [] : [photo],
      kind: 'product',
      districtId: 'd',
      districtLabel: '',
      status: status,
      businessId: businessId,
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1400 * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

Future<void> _confirmReason(WidgetTester tester, String reason, String confirm) async {
  await tester.pumpAndSettle();
  final button = find.widgetWithText(TextButton, confirm);
  expect(tester.widget<TextButton>(button).onPressed, isNull, reason: 'сабабсиз блокланмайди');
  await tester.enterText(find.byKey(const ValueKey('prod_admin_reason')), reason);
  await tester.pump();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('Business: блок ҳолати', () {
    test('блокланган ҳужжат: координата blockedGeo\'дан, isBlocked', () {
      final b = Business.tryFromMap('b1', {
        'ownerId': _owner,
        'name': 'Кийим',
        'category': 'retail',
        'status': 'blocked',
        'blockedGeo': {'lat': 41.8, 'lng': 60.3},
      });
      expect(b, isNotNull);
      expect([b!.isBlocked, b.lat, b.lng], [true, 41.8, 60.3]);
    });

    test('координатасиз ва blockedGeo\'сиз ҳужжат — null (эски APK блокланганни харитада чизмайди)', () {
      expect(Business.tryFromMap('b1', {'ownerId': _owner, 'name': 'X', 'category': 'retail', 'status': 'blocked'}), isNull);
    });

    test('status йўқ ёки нотаниш — active (эски ҳужжатлар)', () {
      final a = Business.tryFromMap('a', {'name': 'A', 'category': 'retail', 'lat': 41.0, 'lng': 60.0})!;
      final b = Business.tryFromMap('b', {'name': 'B', 'category': 'retail', 'lat': 41.0, 'lng': 60.0, 'status': 'hidden'})!;
      expect([a.isBlocked, b.isBlocked], [false, false]);
    });
  });

  group('ShopAdminScreen', () {
    testWidgets('нотўғри телефон — хато, сервер чақирилмайди', (tester) async {
      final repo = _FakeRepo();
      await _pump(tester, ShopAdminScreen(repository: repo, shopRepository: _FakeShop()));
      await tester.enterText(find.byKey(const ValueKey('shop_admin_phone')), '12345');
      await tester.tap(find.byKey(const ValueKey('shop_admin_open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('тўлиқ киритинг'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('сўнгги маҳсулот босилса — шу эга дўкони, йўналишлари; бутун дўкон ва йўналиш блоклари сабаб билан', (tester) async {
      final repo = _FakeRepo(mine: [_biz('b1', 'Сидабилла — Кийим')]);
      final shop = _FakeShop(
        shop: const TvShop(ownerPhone: _owner, name: 'Сидабилла'),
        recent: [_item('r1', 'Кўйлак', status: 'blocked')],
      );
      await _pump(tester, ShopAdminScreen(repository: repo, shopRepository: shop));
      expect(find.textContaining('Блокланган · 5000 сўм · асосий дўкон'), findsOneWidget, reason: 'барча ҳолатдаги маҳсулот кўринади');

      await tester.tap(find.byKey(const ValueKey('shop_admin_recent_r1')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['byOwner:$_owner']);
      expect(find.text('Сидабилла'), findsOneWidget);
      expect(find.text('Сидабилла — Кийим'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shop_admin_shop_block')));
      await _confirmReason(tester, 'фирибгарлик', 'Блоклаш');
      expect(repo.calls, contains('shop:$_owner:blocked:фирибгарлик'));

      await tester.tap(find.byKey(const ValueKey('shop_admin_biz_block_b1')));
      await _confirmReason(tester, 'сохта дўкон', 'Блоклаш');
      expect(repo.calls, contains('biz:b1:blocked:сохта дўкон'));
    });

    testWidgets('блокланган дўкон — «Очиш»; асосий дўкон маҳсулотлари ўз дўкони сўрови билан', (tester) async {
      final repo = _FakeRepo();
      final shop = _FakeShop(
        shop: const TvShop(ownerPhone: _owner, name: 'Сидабилла', status: 'blocked'),
        items: [_item('a', 'Нон'), _item('b', 'Йўналишники', businessId: 'b1')],
      );
      await _pump(tester, ShopAdminScreen(repository: repo, shopRepository: shop));
      await tester.enterText(find.byKey(const ValueKey('shop_admin_phone')), '+998 90 111-11-11');
      await tester.tap(find.byKey(const ValueKey('shop_admin_open')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Дўконни блокдан чиқариш'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shop_admin_main_products')));
      await tester.pumpAndSettle();
      expect(shop.calls, contains('own:$_owner:false'));
      expect(find.text('Нон'), findsOneWidget);
      expect(find.text('Йўналишники'), findsNothing, reason: 'асосий дўконда фақат businessId\'сизлари');
      await tester.tap(find.text('Ёпиш'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('shop_admin_shop_block')));
      await _confirmReason(tester, 'текширилди', 'Очиш');
      expect(repo.calls, contains('shop:$_owner:active:текширилди'));
    });

    testWidgets('сервер SHOP_BLOCKED қайтарса — тушунарли матн', (tester) async {
      final repo = _FakeRepo(mine: [_biz('b1', 'Кийим', status: 'blocked')])
        ..failWith = FirebaseFunctionsException(message: 'x', code: 'failed-precondition', details: {'code': 'SHOP_BLOCKED'});
      await _pump(tester, ShopAdminScreen(repository: repo, shopRepository: _FakeShop()));
      await tester.enterText(find.byKey(const ValueKey('shop_admin_phone')), _owner);
      await tester.tap(find.byKey(const ValueKey('shop_admin_open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shop_admin_biz_block_b1')));
      await _confirmReason(tester, 'текширилди', 'Очиш');
      expect(find.text('Аввал онлайн дўконнинг блокини олинг'), findsOneWidget);
    });
  });

  group('BusinessAdminScreen: блоклаш', () {
    testWidgets('блоклаш тугмаси сабаб билан adminSetStatus; блокланган — белги ва «Очиш»', (tester) async {
      final repo = _FakeRepo(mine: [_biz('b1', 'Кийим'), _biz('b2', 'Техника', status: 'blocked')]);
      await _pump(tester, BusinessAdminScreen(repository: repo));
      expect(find.textContaining('БЛОКЛАНГАН'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_admin_block_b1')));
      await _confirmReason(tester, 'сохта', 'Блоклаш');
      expect(repo.calls, ['biz:b1:blocked:сохта']);
      await tester.tap(find.byKey(const ValueKey('biz_admin_block_b2')));
      await _confirmReason(tester, 'текширилди', 'Очиш');
      expect(repo.calls.last, 'biz:b2:active:текширилди');
    });
  });

  group('BusinessProductsAdminDialog: асосий дўкон', () {
    testWidgets('Business.ownShop — fetchOwnShopItems (блокланган ва кутилаётган ҳам)', (tester) async {
      final shop = _FakeShop(items: [_item('a', 'Нон'), _item('c', 'Блокли', status: 'blocked')]);
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => BusinessProductsAdminDialog(
                  business: Business.ownShop(ownerId: _owner, name: 'Сидабилла'),
                  repo: _FakeRepo(),
                  shopRepository: shop,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(shop.calls, ['own:$_owner:false']);
      expect(find.text('Нон'), findsOneWidget);
      expect(find.text('Блокли'), findsOneWidget);
      expect(find.textContaining('асосий дўкон'), findsOneWidget);
    });
  });

  group('BusinessProductsScreen (эга): блок', () {
    testWidgets('йўналиш блокланган — огоҳлантириш, «қўшиш» тугмаси йўқ, блокланган маҳсулот белгиси', (tester) async {
      final shop = _FakeShop(items: [_item('a', 'Нон', status: 'blocked', businessId: 'b1')]);
      await _pump(tester, BusinessProductsScreen(business: _biz('b1', 'Кийим', status: 'blocked'), repository: shop));
      expect(find.byKey(const ValueKey('bizprod_blocked_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsNothing);
      expect(find.textContaining('bizprod_status_blocked'), findsOneWidget);
    });

    testWidgets('бутун онлайн дўкон блокланган (tv_shops.status) — асосий дўкон экранида ҳам огоҳлантириш', (tester) async {
      final shop = _FakeShop(shop: const TvShop(ownerPhone: _owner, name: 'С', status: 'blocked'), items: [_item('a', 'Нон')]);
      await _pump(tester, BusinessProductsScreen(business: Business.ownShop(ownerId: _owner, name: 'С'), repository: shop));
      expect(find.byKey(const ValueKey('bizprod_blocked_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsNothing);
    });

    testWidgets('блок йўқ — огоҳлантириш йўқ, «қўшиш» бор', (tester) async {
      final shop = _FakeShop(shop: const TvShop(ownerPhone: _owner, name: 'С'), items: [_item('a', 'Нон')]);
      await _pump(tester, BusinessProductsScreen(business: Business.ownShop(ownerId: _owner, name: 'С'), repository: shop));
      expect(find.byKey(const ValueKey('bizprod_blocked_banner')), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
    });
  });

  group('TvShopItemDetailScreen: очилганда ҳолат қайта текширилади', () {
    testWidgets('рўйхатда фаол эди, серверда блокланган — «вақтинча мавжуд эмас», қўнғироқ йўқ', (tester) async {
      await _pump(
        tester,
        TvShopItemDetailScreen(item: _item('a', 'Нон'), loadLatest: (_) async => _item('a', 'Нон', status: 'blocked')),
      );
      expect(find.byKey(const ValueKey('unavailable_product_unavailable')), findsOneWidget);
      expect(find.text('Нон'), findsNothing);
    });

    testWidgets('ҳужжат ўчириб юборилган (null) — «вақтинча мавжуд эмас»', (tester) async {
      await _pump(tester, TvShopItemDetailScreen(item: _item('a', 'Нон'), loadLatest: (_) async => null));
      expect(find.byKey(const ValueKey('unavailable_product_unavailable')), findsOneWidget);
    });

    testWidgets('фаол — маҳсулот кўринади, янги маълумот (нарх/ном) олинади', (tester) async {
      await _pump(
        tester,
        TvShopItemDetailScreen(item: _item('a', 'Нон'), loadLatest: (_) async => _item('a', 'Нон (янги)')),
      );
      expect(find.byKey(const ValueKey('unavailable_product_unavailable')), findsNothing);
      expect(find.text('Нон (янги)'), findsWidgets);
    });

    testWidgets('тармоқ хатоси — қўлдаги фаол нусха кўрсатилади (синмайди)', (tester) async {
      await _pump(tester, TvShopItemDetailScreen(item: _item('a', 'Нон'), loadLatest: (_) async => throw StateError('offline')));
      expect(find.byKey(const ValueKey('unavailable_product_unavailable')), findsNothing);
      expect(find.text('Нон'), findsWidgets);
    });
  });
}
