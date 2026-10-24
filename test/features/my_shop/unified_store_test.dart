import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/business_products_screen.dart';
import 'package:ava_gurlan/features/my_shop/my_shop_entry.dart';
import 'package:ava_gurlan/features/my_shop/my_shop_presence.dart';
import 'package:ava_gurlan/features/my_shop/screens/main_shop_screen.dart';
import 'package:ava_gurlan/features/my_shop/screens/my_shop_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ягона омбор (2026-10-24): Аҳоли бозорининг барча чакана маҳсулоти `tv_shop_items`да — эганинг ўз
/// дўкони (`businessId` бўш) ва қўшимча дўконлар битта каталог/форма экранидан фойдаланади.
/// Локализация делегати АТАЙЛАБ уланмаган: `context.tr` калитнинг ўзини қайтаради.

const _phone = '998901111111';

class _FakeShop implements TvShopRepository {
  _FakeShop([List<TvShopItem>? items]) : items = items ?? [];

  List<TvShopItem> items;
  final calls = <String>[];
  TvShopItem? created;

  @override
  Future<List<TvShopItem>> fetchOwnShopItems(String ownerPhone, {bool onlyActive = false}) async {
    calls.add('own:$ownerPhone');
    return TvShopRepository.visibleOwnShopItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  @override
  Future<List<TvShopItem>> fetchByBusiness(String businessId,
      {String ownerPhone = '', bool onlyActive = true, int limit = 200}) async {
    calls.add('business:$businessId');
    return const [];
  }

  @override
  Future<void> ensureShop({required String ownerPhone, required String name}) async =>
      calls.add('ensureShop:$ownerPhone:$name');

  @override
  Future<String> createItem(TvShopItem item) async {
    created = item;
    calls.add('create');
    return 'item1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

TvShopItem _item(String id, {String title = 'Товар', String owner = _phone, String status = 'active', String businessId = ''}) =>
    TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'x',
      title: title,
      price: 1000,
      photoUrl: 'https://x/$id.jpg',
      photoUrls: ['https://x/$id.jpg'],
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: '',
      status: status,
      businessId: businessId,
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420 * 2, 1200 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

Business _own({String name = 'Barakat'}) => Business.ownShop(ownerId: _phone, name: name, districtId: 'gurlan');

void main() {
  group('Business.ownShop', () {
    test('харитасиз ўз дўкони: id бўш, isOwnShop; ҳақиқий объект — йўқ', () {
      expect(_own().isOwnShop, isTrue);
      expect(_own().id, isEmpty);
      expect(_own().category, BusinessCategory.retail);
      const real = Business(
          id: 'b1', ownerId: _phone, name: 'x', category: BusinessCategory.retail, phone: _phone, lat: 1, lng: 2);
      expect(real.isOwnShop, isFalse);
    });
  });

  group('TvShopRepository.visibleOwnShopItems', () {
    test('фақат businessId бўш, ўчирилмаган ва шу эганики; онлайн дўкон объект маҳсулотлари аралашмайди', () {
      final all = [
        _item('own1'),
        _item('own2', status: 'pending'),
        _item('biz', businessId: 'b1'),
        _item('del', status: 'deleted'),
        _item('alien', owner: '998909999999'),
      ];
      final mine = TvShopRepository.visibleOwnShopItems(all, ownerPhone: '+998 90 111 11 11');
      expect(mine.map((e) => e.id).toSet(), {'own1', 'own2'});
      final active = TvShopRepository.visibleOwnShopItems(all, ownerPhone: _phone, onlyActive: true);
      expect(active.map((e) => e.id), ['own1']);
    });
  });

  group('BusinessProductsScreen — эганинг ўз дўкони', () {
    testWidgets('рўйхат `fetchOwnShopItems`дан (businessId сўрови йўқ); сарлавҳада дўкон номи', (tester) async {
      final shop = _FakeShop([_item('a', title: 'Куртка'), _item('b', title: 'Кепка'), _item('c', businessId: 'b9')]);
      await _pump(tester, BusinessProductsScreen(business: _own(), repository: shop));
      expect(find.text('Куртка'), findsOneWidget);
      expect(find.text('Кепка'), findsOneWidget);
      expect(shop.calls, ['own:$_phone']);
      expect(find.text('Barakat'), findsOneWidget, reason: 'AppBar сарлавҳаси');
      expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
    });

    testWidgets('embedded: ўз AppBar и йўқ; бўш рўйхатда «қўшиш» тугмаси бор', (tester) async {
      await _pump(tester, BusinessProductsScreen(business: _own(), repository: _FakeShop(), embedded: true));
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('bizprod_empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
    });

    testWidgets('openFormOnStart: форма дарҳол очилади, ёпилгач рўйхат турибди', (tester) async {
      await _pump(
        tester,
        BusinessProductsScreen(business: _own(), repository: _FakeShop(), embedded: true, openFormOnStart: true),
      );
      expect(find.byType(BusinessProductFormScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(BusinessProductFormScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BusinessProductFormScreen), findsNothing);
      expect(find.byKey(const ValueKey('bizprod_fab')), findsOneWidget);
    });
  });

  group('BusinessProductFormScreen — эганинг ўз дўкони', () {
    testWidgets('яратиш: businessId ЙЎҚ, ном = дўкон номи, расм ва нарх; ensureShop шу ном билан', (tester) async {
      final shop = _FakeShop();
      await _pump(
        tester,
        BusinessProductFormScreen(
          business: _own(),
          repository: shop,
          ownerPhone: _phone,
          pickPhotos: (room) async => ['a.jpg', 'b.jpg'],
          uploadPhotos: (phone, paths) async => [for (final p in paths) 'https://cdn/$p'],
          addVideo: (ctx, id) async {},
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Куртка');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '420 000');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();

      final c = shop.created!;
      expect(c.businessId, isEmpty);
      expect(c.toMap().containsKey('businessId'), isFalse, reason: 'rules: businessId бўш қатор ёзилмайди');
      expect(c.ownerName, 'Barakat');
      expect(c.ownerPhone, _phone);
      expect(c.price, 420000);
      expect(c.photoUrls.length, 2);
      expect(c.status, 'active');
      expect(c.districtId, 'gurlan');
      expect(shop.calls, containsAllInOrder(['ensureShop:$_phone:Barakat', 'create']));
    });
  });

  group('MainShopScreen — Аҳоли бозори сегменти ягона каталог', () {
    testWidgets('ном ўқилмаса ҳам каталог очилади (спиннерда қолмайди)', (tester) async {
      await _pump(
        tester,
        MainShopScreen(
          phone: _phone,
          loadName: () async => throw StateError('offline'),
          saveName: (_) async {},
          wholesaleView: (_) => const SizedBox.shrink(),
          // retailView берилмаган: ҳақиқий каталог қурилади, лекин унинг репозитарийси Firebase талаб қилади —
          // шунинг учун бу ерда фақат спиннердан чиқишини `retailView` билан текширамиз.
          retailView: (_) => const Text('CATALOG'),
        ),
      );
      expect(find.text('CATALOG'), findsOneWidget);
    });
  });

  group('Аҳоли бозоридан кириш йўллари', () {
    Future<void> host(WidgetTester tester, Future<void> Function(BuildContext) run) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(child: ElevatedButton(onPressed: () => run(context), child: const Text('go'))),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('«＋»: телефон бўлмаса — форма очилмайди, содда хабар', (tester) async {
      final pushed = <Widget>[];
      await host(
        tester,
        (c) => openNewProduct(c, ownPhone: () async => '', push: (s) async => pushed.add(s)),
      );
      expect(pushed, isEmpty);
      expect(find.text('need_phone_profile'), findsOneWidget);
    });

    testWidgets('«＋»: форма ўз дўкони номи билан очилади', (tester) async {
      final pushed = <Widget>[];
      await host(
        tester,
        (c) => openNewProduct(
          c,
          ownPhone: () async => _phone,
          loadName: (_) async => 'Barakat kiyim',
          push: (s) async => pushed.add(s),
        ),
      );
      final form = pushed.single as BusinessProductFormScreen;
      expect(form.business.isOwnShop, isTrue);
      expect(form.business.name, 'Barakat kiyim');
      expect(form.business.ownerId, _phone);
    });

    testWidgets('«＋»: ном ўқилмаса — «Менинг дўконим» номи билан очилади (форма тўхтамайди)', (tester) async {
      final pushed = <Widget>[];
      await host(
        tester,
        (c) => openNewProduct(
          c,
          ownPhone: () async => _phone,
          loadName: (_) async => throw StateError('offline'),
          push: (s) async => pushed.add(s),
        ),
      );
      final form = pushed.single as BusinessProductFormScreen;
      expect(form.business.name, 'my_shop_title');
    });
    testWidgets('«Менинг дўконим» тугмаси: дўкони бор эгага рўйхат; телефонсиз — хабар', (tester) async {
      final pushed = <Widget>[];
      await host(
        tester,
        (c) => openMyShopFromMarket(
          c,
          ownPhone: () async => _phone,
          loadPresence: (_) async => const MyShopPresence(retail: true, otherShops: 1),
          push: (s) async => pushed.add(s),
        ),
      );
      expect(pushed.single, isA<MyShopScreen>());

      pushed.clear();
      await host(
        tester,
        (c) => openMyShopFromMarket(c, ownPhone: () async => '', push: (s) async => pushed.add(s)),
      );
      expect(pushed, isEmpty);
      expect(find.text('need_phone_profile'), findsOneWidget);
    });
  });
}
