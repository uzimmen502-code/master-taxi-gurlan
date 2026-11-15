// «Бозорлар» 2b (эга 2026-11-15): сотувчи рўйхатида ҳолат нишонлари ва «Янгилаш»; таҳрирда статус юборилмайди.

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/business_map/screens/business_products_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:ava_gurlan/features/tv_market/services/listing_renew_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeShop implements TvShopRepository {
  _FakeShop(this.items);

  List<TvShopItem> items;
  int fetches = 0;
  Map<String, dynamic>? patch;

  @override
  Future<List<TvShopItem>> fetchByBusiness(String businessId,
      {String ownerPhone = '', bool onlyActive = true, int limit = 200}) async {
    fetches++;
    return TvShopRepository.visibleBusinessItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  @override
  Future<TvShop?> fetchShop(String ownerPhone) async => null;

  @override
  Future<void> updateItem(String itemId, Map<String, dynamic> p) async => patch = p;

  TvShopItem? created;

  @override
  Future<void> ensureShop({required String ownerPhone, required String name}) async {}

  @override
  Future<String> createItem(TvShopItem item) async {
    created = item;
    return 'new1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final _biz = Business(
  id: 'b1',
  ownerId: '998901111111',
  name: 'Боғ',
  category: BusinessCategory.retail,
  phone: '998901234567',
  lat: 41.3,
  lng: 69.2,
  districtId: 'gurlan',
);

TvShopItem _it(String id, String status, {DateTime? expiresAt, String reason = ''}) => TvShopItem(
      id: id,
      ownerPhone: '998901111111',
      ownerName: 'x',
      title: 'Товар $id',
      price: 1000,
      photoUrl: '',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: '',
      status: status,
      businessId: 'b1',
      expiresAt: expiresAt,
      rejectReason: reason,
      createdAt: DateTime(2026, 11, 1),
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

/// Форма сақлангач `pop(true)` қилади — илдиз йўл бўлмасин: хост экрандан очилади.
Future<void> _pushForm(WidgetTester tester, Widget form) async {
  await _pump(
    tester,
    Builder(
      key: UniqueKey(),
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<bool>(builder: (_) => form)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('нишонлар: pending / rejected+сабаб / expired+Янгилаш / active «N кун»; эски ҳужжат — нишонсиз',
      (tester) async {
    final shop = _FakeShop([
      _it('p', 'pending'),
      _it('r', 'rejected', reason: 'Расм сифатсиз'),
      _it('e', 'expired'),
      _it('a', 'active', expiresAt: DateTime.now().add(const Duration(days: 10, hours: 1))),
      _it('o', 'active'),
    ]);
    await _pump(tester, BusinessProductsScreen(business: _biz, repository: shop, renewService: ListingRenewService(invoke: (_, __) async => null)));

    expect(find.text('listing_mod_status_pending'), findsOneWidget);
    expect(find.text('listing_mod_status_rejected'), findsOneWidget);
    expect(find.byKey(const ValueKey('bizprod_reject_reason_r')), findsOneWidget);
    expect(find.text('listing_mod_status_expired'), findsOneWidget);
    expect(find.byKey(const ValueKey('bizprod_renew_e')), findsOneWidget);
    expect(find.byKey(const ValueKey('bizprod_renew_r')), findsNothing, reason: 'рад этилган — янгилаш йўқ');
    expect(find.byKey(const ValueKey('bizprod_days_left_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('bizprod_badge_o')), findsNothing);
    expect(find.byKey(const ValueKey('bizprod_days_left_o')), findsNothing, reason: 'expiresAt йўқ — аввалгидек');
    expect(find.byKey(const ValueKey('bizprod_promote_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('bizprod_promote_p')), findsNothing, reason: 'фақат фаол реклама қилинади');
  });

  testWidgets('«Янгилаш» → renewMarketListing(tv_shop_items, id), «юборилди» ва рўйхат янгиланади', (tester) async {
    final shop = _FakeShop([_it('e', 'expired')]);
    final calls = <String>[];
    await _pump(
      tester,
      BusinessProductsScreen(
        business: _biz,
        repository: shop,
        renewService: ListingRenewService(invoke: (name, p) async {
          calls.add('$name:${p['collection']}:${p['id']}');
          shop.items = [_it('e', 'pending')];
          return {'ok': true};
        }),
      ),
    );
    final before = shop.fetches;
    await tester.tap(find.byKey(const ValueKey('bizprod_renew_e')));
    await tester.pumpAndSettle();
    expect(calls, ['renewMarketListing:tv_shop_items:e']);
    expect(find.text('listing_mod_submitted'), findsOneWidget);
    expect(shop.fetches, before + 1);
    expect(find.text('listing_mod_status_pending'), findsOneWidget);
  });

  testWidgets('«Янгилаш» хатоси: умумий матн (сервер матни/код экранда эмас), рўйхат ўзгармайди', (tester) async {
    final shop = _FakeShop([_it('e', 'expired')]);
    await _pump(
      tester,
      BusinessProductsScreen(
        business: _biz,
        repository: shop,
        renewService: ListingRenewService(
          invoke: (_, __) async =>
              throw FirebaseFunctionsException(code: 'permission-denied', message: 'NOT_OWNER raw', details: {'code': 'NOT_OWNER'}),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('bizprod_renew_e')));
    await tester.pumpAndSettle();
    expect(find.text('listing_mod_renew_failed'), findsOneWidget);
    expect(find.textContaining('NOT_OWNER'), findsNothing);
    expect(find.byKey(const ValueKey('bizprod_renew_e')), findsOneWidget, reason: 'қайта уриниш мумкин');
  });

  testWidgets('яратиш: status=pending, модерация майдонлари ёзилмайди, «текширувга юборилди»', (tester) async {
    final shop = _FakeShop([]);
    await _pushForm(
      tester,
      BusinessProductFormScreen(
        business: _biz,
        repository: shop,
        ownerPhone: '998901111111',
        pickPhotos: (room) async => ['p.jpg'],
        uploadPhotos: (phone, paths) async => ['https://cdn/p.jpg'],
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Олма');
    await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bizprod_save')));
    await tester.pumpAndSettle();
    expect(shop.created!.status, 'pending');
    final m = shop.created!.toMap();
    for (final k in ['submittedAt', 'expiresAt', 'moderatedAt', 'rejectReason']) {
      expect(m.containsKey(k), isFalse, reason: k);
    }
    expect(find.byKey(const ValueKey('bizprod_snack_submitted')), findsOneWidget);
    expect(find.text('listing_mod_submitted'), findsOneWidget);
  });

  testWidgets('таҳрир: статус ЮБОРИЛМАЙДИ (rules); контент ўзгарса — «текширувга юборилди», акс ҳолда «Сақланди»',
      (tester) async {
    final shop = _FakeShop([]);
    await _pushForm(tester, BusinessProductFormScreen(business: _biz, existing: _it('a', 'active'), repository: shop, ownerPhone: '998901111111'));
    await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Янги ном');
    await tester.tap(find.byKey(const ValueKey('bizprod_save')));
    await tester.pumpAndSettle();
    expect(shop.patch!.containsKey('status'), isFalse);
    expect(shop.patch!['title'], 'Янги ном');
    expect(find.byKey(const ValueKey('bizprod_snack_submitted')), findsOneWidget);

    final shop2 = _FakeShop([]);
    await _pushForm(tester, BusinessProductFormScreen(business: _biz, existing: _it('r', 'rejected'), repository: shop2, ownerPhone: '998901111111'));
    await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Бошқа ном');
    await tester.tap(find.byKey(const ValueKey('bizprod_save')));
    await tester.pumpAndSettle();
    expect(shop2.patch!.containsKey('status'), isFalse);
    expect(find.byKey(const ValueKey('bizprod_snack_saved')), findsOneWidget, reason: 'рад этилган — сервер қайта юбормайди');
  });
}
