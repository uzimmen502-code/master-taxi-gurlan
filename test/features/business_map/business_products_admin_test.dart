import 'package:ava_gurlan/features/admin_web/screens/business_products_admin_dialog.dart';
import 'package:ava_gurlan/features/business_map/data/business_repository.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo extends BusinessRepository {
  final calls = <String>[];
  Object? failWith;

  @override
  Future<void> adminUpdateProduct(
    String itemId, {
    required String reason,
    String? title,
    int? price,
    String? description,
    String? kind,
    String? status,
  }) async {
    calls.add('update:$itemId:$title:$price:${description ?? '-'}:${status ?? '-'}:$reason');
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> adminDeleteProduct(String itemId, {required String reason}) async =>
      calls.add('delete:$itemId:$reason');
}

class _FakeShop implements TvShopRepository {
  _FakeShop(this.items);

  List<TvShopItem> items;
  final calls = <String>[];

  @override
  Future<List<TvShopItem>> fetchByBusiness(
    String businessId, {
    String ownerPhone = '',
    bool onlyActive = true,
    int limit = 200,
  }) async {
    calls.add('fetch:$businessId:$ownerPhone:$onlyActive');
    return TvShopRepository.visibleBusinessItems(items, ownerPhone: ownerPhone, onlyActive: onlyActive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

const _biz = Business(
  id: 'b1',
  ownerId: '998901111111',
  name: 'Мой Дўкон',
  category: BusinessCategory.retail,
  phone: '998901234567',
  lat: 41.3,
  lng: 69.2,
);

TvShopItem _item(String id, String title, {String status = 'active', int price = 0, String owner = '998901111111'}) => TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'x',
      title: title,
      price: price,
      photoUrl: 'https://x/$id.jpg',
      photoUrls: ['https://x/$id.jpg'],
      kind: 'product',
      districtId: 'd',
      districtLabel: '',
      status: status,
      businessId: 'b1',
    );

Future<void> _open(WidgetTester tester, BusinessRepository repo, TvShopRepository shop) async {
  tester.view.physicalSize = const Size(1200 * 2, 900 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showDialog<void>(
            context: ctx,
            builder: (_) => BusinessProductsAdminDialog(business: _biz, repo: repo, shopRepository: shop),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('админ барча (ўчирилмаган) маҳсулотни кўради — кутилаётган, блокланган, бошқа эга ёзган ҳам', (tester) async {
    final shop = _FakeShop([
      _item('a', 'Нон', price: 5000),
      _item('b', 'Блокли', status: 'blocked'),
      _item('c', 'Кутилмоқда', status: 'pending'),
      _item('d', 'Ўчирилган', status: 'deleted'),
      _item('e', 'Ёт эга', owner: '998909999999'),
    ]);
    await _open(tester, _FakeRepo(), shop);
    expect(shop.calls.single, 'fetch:b1::false', reason: 'эга фильтри йўқ, фаол бўлмаганлар ҳам');
    for (final t in ['Нон', 'Блокли', 'Кутилмоқда', 'Ёт эга']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Ўчирилган'), findsNothing);
    expect(find.textContaining('Блокланган'), findsOneWidget);
  });

  testWidgets('ўчириш: сабабсиз тугма ўчиқ; сабаб билан adminDeleteProduct', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _FakeShop([_item('a', 'Нон')]));
    await tester.tap(find.byTooltip('Ўчириш'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(TextButton, 'Ўчириш');
    expect(tester.widget<TextButton>(confirm).onPressed, isNull, reason: 'сабабсиз ўчирилмайди');
    await tester.enterText(find.byKey(const ValueKey('prod_admin_reason')), 'ab');
    await tester.pump();
    expect(tester.widget<TextButton>(confirm).onPressed, isNull, reason: '3 белгидан кам — рад');
    await tester.enterText(find.byKey(const ValueKey('prod_admin_reason')), 'соxта маҳсулот');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(repo.calls, ['delete:a:соxта маҳсулот']);
  });

  testWidgets('таҳрир: сабабсиз сақланмайди; нотўғри нарх рад; тўғри — adminUpdateProduct, блоклаш status=blocked', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _FakeShop([_item('a', 'Нон', price: 5000)]));
    await tester.tap(find.byTooltip('Таҳрирлаш'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prod_admin_save')));
    await tester.pumpAndSettle();
    expect(find.text('Сабабни ёзинг'), findsOneWidget);
    expect(repo.calls, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('prod_admin_edit_reason')), 'имло');
    await tester.enterText(find.byKey(const ValueKey('prod_admin_price')), '12a');
    await tester.tap(find.byKey(const ValueKey('prod_admin_save')));
    await tester.pumpAndSettle();
    expect(find.text('Нархни рақам билан киритинг'), findsOneWidget);
    expect(repo.calls, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('prod_admin_title')), 'Нон (янги)');
    await tester.enterText(find.byKey(const ValueKey('prod_admin_price')), '7000');
    await tester.tap(find.byKey(const ValueKey('prod_admin_blocked')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prod_admin_save')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['update:a:Нон (янги):7000:-:blocked:имло'], reason: 'description ўзгармаган — юборилмайди');
  });

  testWidgets('сервер хато берса — диагностика коди кўрсатилади, диалог ёпилмайди', (tester) async {
    final repo = _FakeRepo()..failWith = StateError('x');
    await _open(tester, repo, _FakeShop([_item('a', 'Нон')]));
    await tester.tap(find.byTooltip('Таҳрирлаш'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prod_admin_title')), 'Нон 2');
    await tester.enterText(find.byKey(const ValueKey('prod_admin_edit_reason')), 'имло');
    await tester.tap(find.byKey(const ValueKey('prod_admin_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сақлаб бўлмади'), findsOneWidget);
    expect(find.text('Маҳсулотни таҳрирлаш'), findsOneWidget);
  });

  testWidgets('таҳрир: ҳеч нарса ўзгармаса — "Ўзгариш йўқ", сервер чақирилмайди', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _FakeShop([_item('a', 'Нон', price: 5000)]));
    await tester.tap(find.byTooltip('Таҳрирлаш'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prod_admin_edit_reason')), 'имло');
    await tester.tap(find.byKey(const ValueKey('prod_admin_save')));
    await tester.pumpAndSettle();
    expect(find.text('Ўзгариш йўқ'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('блокланганни очиш — status=active юборилади; фақат шу майдон', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _FakeShop([_item('a', 'Нон', price: 5000, status: 'blocked')]));
    await tester.tap(find.byTooltip('Таҳрирлаш'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prod_admin_blocked')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('prod_admin_edit_reason')), 'хато блокланган');
    await tester.tap(find.byKey(const ValueKey('prod_admin_save')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['update:a:null:null:-:active:хато блокланган']);
  });
}